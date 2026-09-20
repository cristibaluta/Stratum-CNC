//
//  MachineAlerts.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#endif

/// Something the person at the machine needs to know about *now* — a tool
/// change waiting on them, an alarm, an error. Deliberately not the same as
/// a line in the terminal log, which is easy to miss mid-job.
struct MachineAlert: Identifiable, Equatable {

    enum Kind: Hashable {
        /// The machine wants a tool swapped (needs the person, then Resume).
        case toolChange
        /// The machine paused the job and we can't tell why.
        case paused
        case alarm
        case error
        case connectionLost
        /// A job was already suspended on the machine when we connected —
        /// e.g. the app was closed while it waited. Informational: nothing
        /// is going wrong, it's just there to be picked back up.
        case suspendedJob
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String

    /// The alert is about a stopped job that continues when the person says
    /// so, so the dialog offers a Resume button.
    var offersResume: Bool {
        kind == .toolChange || kind == .paused || kind == .suspendedJob
    }

    /// Kinds that keep repeating a sound until dismissed — the ones where
    /// the machine is stuck until someone acts.
    var isPersistent: Bool {
        kind != .error && kind != .suspendedJob
    }
}

/// Recognizes alerts in the machine's text output.
///
/// Alarm and error lines follow grbl/Smoothieware conventions (`ALARM: …`,
/// `error: …`, `!!` for a halt). The tool-change matching is a *heuristic*:
/// nothing in this project records the exact wording the firmware uses when
/// it wants a tool swapped, so it looks for a line that mentions a tool and
/// a change/insert/load-type verb. Capture what a real M6 prints in the
/// terminal and tighten `isToolChangePrompt` to that.
enum MachineAlertRules {

    static func alert(forLine line: String) -> MachineAlert? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !text.isEmpty, lower != "ok", !lower.hasPrefix("ok ") else { return nil }

        if lower.hasPrefix("alarm") || lower.hasPrefix("!!") {
            return MachineAlert(kind: .alarm, title: "Machine alarm", message: stripPrefix(text))
        }
        if lower.hasPrefix("error") {
            return MachineAlert(kind: .error, title: "Machine error", message: stripPrefix(text))
        }
        if isToolChangePrompt(lower) {
            let title = toolNumber(in: lower).map { "Tool change needed (T\($0))" } ?? "Tool change needed"
            return MachineAlert(kind: .toolChange, title: title, message: text)
        }
        return nil
    }

    static func isToolChangePrompt(_ lower: String) -> Bool {
        guard lower.contains("tool") else { return false }
        let asks = ["change", "insert", "install", "load", "replace", "swap"]
        let finished = ["done", "complete", "finish", "success"]
        return asks.contains { lower.contains($0) } && !finished.contains { lower.contains($0) }
    }

    static func toolNumber(in lower: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\bt(?:ool)?\s*#?\s*(\d+)\b"#),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let range = Range(match.range(at: 1), in: lower) else { return nil }
        return Int(lower[range])
    }

    /// "ALARM: Hard limit" → "Hard limit".
    private static func stripPrefix(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: #"^(?i)(alarm|error|!!)\s*:?\s*"#, with: "", options: .regularExpression
        )
        return stripped.isEmpty ? text : stripped
    }
}

/// Owns the queue of alerts and everything that makes them hard to miss:
/// a modal dialog in the app (`machineAlerts(_:onResume:)` below), a bouncing
/// Dock icon, a sound that repeats while the machine is stuck, and — when the
/// app isn't frontmost — a time-sensitive system notification.
@MainActor
final class MachineAlertCenter: ObservableObject {

    @Published private(set) var queue: [MachineAlert] = []

    var current: MachineAlert? { queue.first }

    private var lastPosted: [MachineAlert.Kind: Date] = [:]
    private var lastKey: (key: String, date: Date)?
    private var soundTask: Task<Void, Never>?
    #if os(macOS)
    private var attentionRequest: Int?
    #endif

    // MARK: Posting

    func post(_ alert: MachineAlert) {
        // A status change and the line explaining it usually both arrive.
        let key = "\(alert.kind)|\(alert.message)"
        if let last = lastKey, last.key == key, Date().timeIntervalSince(last.date) < 5 { return }
        lastKey = (key, Date())
        lastPosted[alert.kind] = Date()

        // A specific tool-change prompt replaces the generic "paused" one.
        if alert.kind == .toolChange {
            queue.removeAll { $0.kind == .paused }
        }
        queue.append(alert)

        attract(for: alert)
        if !isAppActive {
            postSystemNotification(alert)
        }
    }

    func wasPosted(_ kind: MachineAlert.Kind, within seconds: TimeInterval) -> Bool {
        guard let date = lastPosted[kind] else { return false }
        return Date().timeIntervalSince(date) < seconds
    }

    /// Removes alerts whose cause has gone away by itself — the person
    /// resumed at the machine, or cleared the alarm there.
    func resolve(_ kinds: Set<MachineAlert.Kind>) {
        queue.removeAll { kinds.contains($0.kind) }
        if queue.isEmpty { stopAttracting() }
    }

    func dismiss() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        if queue.isEmpty { stopAttracting() }
    }

    // MARK: Getting attention

    private var isAppActive: Bool {
        #if os(macOS)
        return NSApp.isActive
        #else
        return false
        #endif
    }

    private func attract(for alert: MachineAlert) {
        #if os(macOS)
        // Bounces the Dock icon until the app is brought forward.
        if attentionRequest == nil {
            attentionRequest = NSApp.requestUserAttention(.criticalRequest)
        }
        playSound()
        guard alert.isPersistent, soundTask == nil else { return }
        soundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                self?.playSound()
            }
        }
        #endif
    }

    private func stopAttracting() {
        soundTask?.cancel()
        soundTask = nil
        #if os(macOS)
        if let request = attentionRequest {
            NSApp.cancelUserAttentionRequest(request)
            attentionRequest = nil
        }
        #endif
    }

    #if os(macOS)
    private func playSound() {
        if NSSound(named: "Sosumi")?.play() != true {
            NSSound.beep()
        }
    }
    #endif

    // MARK: System notifications

    /// Asked for when a machine connects rather than at launch, so the
    /// permission prompt appears while someone is at the screen — not for
    /// the first time in the middle of an unattended job.
    func requestAuthorization() {
//        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postSystemNotification(_ alert: MachineAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
//        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Presentation

private struct MachineAlertModifier: ViewModifier {
    @ObservedObject var alerts: MachineAlertCenter
    let onResume: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            alerts.current?.title ?? "",
            isPresented: Binding(
                get: { alerts.current != nil },
                set: { presented in
                    if !presented { alerts.dismiss() }
                }
            ),
            presenting: alerts.current
        ) { alert in
            if alert.offersResume {
                Button("Resume job") { onResume() }
                Button("Dismiss", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
    }
}

extension View {
    /// Shows `alerts` as a modal dialog over this view until dismissed.
    func machineAlerts(_ alerts: MachineAlertCenter, onResume: @escaping () -> Void) -> some View {
        modifier(MachineAlertModifier(alerts: alerts, onResume: onResume))
    }
}
