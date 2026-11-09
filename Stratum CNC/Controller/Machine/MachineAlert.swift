//
//  MachineAlerts.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import SwiftUI
import UserNotifications
import StratumLink
#if os(macOS)
import AppKit
#endif

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
        if queue.isEmpty {
            stopAttracting()
        }
    }

    func dismiss() {
        guard !queue.isEmpty else {
            return
        }
        queue.removeFirst()
        if queue.isEmpty {
            stopAttracting()
        }
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
