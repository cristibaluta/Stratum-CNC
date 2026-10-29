//
//  QuickActionUsage.swift
//  Stratum CNC
//
//  Remembers how often each Quick Start / Libraries tile is used, so the tiles
//  can tint their icons by how much they matter to this user.
//
//  Each click adds 1 to a score that fades with a half-life (`halfLifeDays`),
//  so what you used last month counts for less than what you used today. The
//  tint of a tile is then its score relative to the most used tile.
//

import SwiftUI

/// Every tile that takes part in the usage ranking.
enum QuickActionID: String, CaseIterable {
    case newProject
    case openProjectFolder
    case tryWithoutProject
    case openController
    case importGCode
    case toolsLibrary
    case stockLibrary
}

@MainActor
final class QuickActionUsage: ObservableObject {

    static let shared = QuickActionUsage()

    /// A click loses half its weight after this many days.
    private let halfLifeDays: Double = 30
    /// The top tile only reaches full tint once its (decayed) score gets here,
    /// so a brand new install doesn't light up whatever was clicked first.
    private let fullTintScore: Double = 5
    /// Relative usage below this stays completely untinted.
    private let noTintBelow: Double = 0.08

    private let defaultsKey = "quickActionUsage.v1"
    private let defaults: UserDefaults

    private struct Entry {
        var score: Double
        var updated: Date
    }

    private var entries: [String: Entry] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Recording

    func recordClick(_ id: QuickActionID, now: Date = Date()) {
        var entry = entries[id.rawValue] ?? Entry(score: 0, updated: now)
        entry.score = decayedScore(entry, at: now) + 1
        entry.updated = now
        entries[id.rawValue] = entry
        save()
        objectWillChange.send()
    }

    /// Forgets all recorded clicks, so every tile goes back to untinted.
    func reset() {
        entries.removeAll()
        defaults.removeObject(forKey: defaultsKey)
        objectWillChange.send()
    }

    // MARK: - Reading

    /// 0 = never / barely used (no tint), 1 = the most used tile (full tint).
    func intensity(for id: QuickActionID, now: Date = Date()) -> Double {
        let scores = QuickActionID.allCases.map { score(for: $0, now: now) }
        guard let maxScore = scores.max(), maxScore > 0 else {
            return 0
        }
        let confidence = min(1, maxScore / fullTintScore)
        let relative = score(for: id, now: now) / maxScore * confidence
        guard relative > noTintBelow else {
            return 0
        }
        return min(1, (relative - noTintBelow) / (1 - noTintBelow))
    }

    // MARK: - Internals

    private func score(for id: QuickActionID, now: Date) -> Double {
        guard let entry = entries[id.rawValue] else {
            return 0
        }
        return decayedScore(entry, at: now)
    }

    private func decayedScore(_ entry: Entry, at now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(entry.updated)) / 86_400
        return entry.score * pow(0.5, days / halfLifeDays)
    }

    private func load() {
        guard let stored = defaults.dictionary(forKey: defaultsKey) as? [String: [String: Double]] else {
            return
        }
        for (key, value) in stored {
            guard let score = value["score"], let updated = value["updated"] else {
                continue
            }
            entries[key] = Entry(score: score, updated: Date(timeIntervalSince1970: updated))
        }
    }

    private func save() {
        let stored = entries.mapValues {
            ["score": $0.score, "updated": $0.updated.timeIntervalSince1970]
        }
        defaults.set(stored, forKey: defaultsKey)
    }
}
