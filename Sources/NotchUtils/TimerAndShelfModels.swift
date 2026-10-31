// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit
import SwiftUI

final class TimerModel: ObservableObject {
    enum State { case idle, running, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var endDate = Date()
    private var pausedRemaining: TimeInterval = 0
    private var finishWork: DispatchWorkItem?

    var onFinished: (() -> Void)?

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch state {
        case .idle: duration
        case .paused: pausedRemaining
        case .running: max(endDate.timeIntervalSince(date), 0)
        }
    }

    func progress(at date: Date = Date()) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }

    func select(minutes: Int) {
        duration = TimeInterval(minutes * 60)
        if state != .idle { reset() }
    }

    func adjust(minutes: Int) {
        let delta = TimeInterval(minutes * 60)
        switch state {
        case .idle:
            duration = min(max(duration + delta, 60), 180 * 60)
        case .paused:
            pausedRemaining = max(pausedRemaining + delta, 1)
            duration = max(duration, pausedRemaining)
            objectWillChange.send()
        case .running:
            let left = max(remaining() + delta, 1)
            duration = max(duration, left)
            run(for: left)
        }
    }

    func toggle() {
        switch state {
        case .idle: run(for: duration)
        case .paused: run(for: pausedRemaining)
        case .running:
            pausedRemaining = remaining()
            finishWork?.cancel()
            state = .paused
        }
    }

    func reset() {
        finishWork?.cancel()
        state = .idle
    }

    private func run(for seconds: TimeInterval) {
        endDate = Date().addingTimeInterval(seconds)
        state = .running
        finishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.state = .idle
            self?.onFinished?()
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

final class ShelfModel: ObservableObject {
    private static let defaultsKey = "shelfPaths"

    @Published private(set) var items: [URL] = []

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func airDrop() {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items)
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: Self.defaultsKey)
    }
}

#if DEMO
extension TimerModel {
    func loadDemo() {
        duration = 25 * 60
        endDate = Date().addingTimeInterval(14 * 60 + 32)
        state = .running
    }
}

extension ShelfModel {
    func loadDemo(_ urls: [URL]) {
        items = urls
    }
}
#endif
