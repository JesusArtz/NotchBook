//
//  ClaudeBridge.swift
//  NotchDrop
//
//  Watches a drop folder that Claude Code hooks write into, and answers the
//  permission requests waiting there.
//

import Combine
import Foundation

struct ClaudeEvent: Identifiable, Equatable {
    enum Kind: String {
        case finished
        case permission
    }

    let id: String
    let kind: Kind
    let cwd: String
    let toolName: String
    let detail: String
    let date: Date

    /// The folder name is what the user recognises, not the whole path.
    var project: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

struct ClaudeBridgeState: Equatable {
    var pending: ClaudeEvent?
    var finishedFlash: ClaudeEvent?
    var recent: [ClaudeEvent] = []

    static let idle = ClaudeBridgeState()

    var hasPending: Bool { pending != nil }
}

class ClaudeBridge {
    static let shared = ClaudeBridge()

    let state: CurrentValueSubject<ClaudeBridgeState, Never> = .init(.idle)

    /// Hooks write here, and read their answer back from the same folder.
    static let inboxURL = documentsDirectory.appendingPathComponent("ClaudeEvents")

    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.5
    private let finishedLinger: TimeInterval = 5
    private let recentLimit = 10

    private var flashClearedAt: Date?

    private init() {
        try? FileManager.default.createDirectory(
            at: Self.inboxURL, withIntermediateDirectories: true
        )
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scan()
    }

    deinit {
        destroy()
    }

    func destroy() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Answering

    func allow(_ event: ClaudeEvent) { respond(to: event, decision: "allow") }
    func deny(_ event: ClaudeEvent) { respond(to: event, decision: "deny") }

    /// Hands the waiting hook back to the terminal's own prompt.
    func defer_(_ event: ClaudeEvent) { respond(to: event, decision: "ask") }

    private func respond(to event: ClaudeEvent, decision: String) {
        let url = Self.inboxURL.appendingPathComponent("response-\(event.id).json")
        let payload = ["decision": decision]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: url)

        var next = state.value
        if next.pending?.id == event.id { next.pending = nil }
        state.send(next)
    }

    // MARK: - Watching

    private func scan() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: Self.inboxURL.path) else { return }

        var next = state.value

        // A request the hook already gave up on should not stay on screen.
        if let pending = next.pending,
           !names.contains("request-\(pending.id).json") {
            next.pending = nil
        }

        for name in names.sorted() {
            let url = Self.inboxURL.appendingPathComponent(name)
            if name.hasPrefix("request-"), name.hasSuffix(".json") {
                guard let event = load(url, kind: .permission),
                      next.pending?.id != event.id
                else { continue }
                // The newest request wins, an older one has likely timed out.
                next.pending = event
                next.recent = ([event] + next.recent).prefix(recentLimit).map { $0 }
            } else if name.hasPrefix("event-"), name.hasSuffix(".json") {
                guard let event = load(url, kind: .finished) else { continue }
                try? manager.removeItem(at: url)
                next.finishedFlash = event
                flashClearedAt = Date().addingTimeInterval(finishedLinger)
                next.recent = ([event] + next.recent).prefix(recentLimit).map { $0 }
            }
        }

        if let clearAt = flashClearedAt, Date() >= clearAt {
            next.finishedFlash = nil
            flashClearedAt = nil
        }

        guard next != state.value else { return }
        state.send(next)
    }

    private func load(_ url: URL, kind: ClaudeEvent.Kind) -> ClaudeEvent? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String
        else { return nil }
        return ClaudeEvent(
            id: id,
            kind: kind,
            cwd: object["cwd"] as? String ?? "",
            toolName: object["tool_name"] as? String ?? "",
            detail: object["detail"] as? String ?? "",
            date: Date(timeIntervalSince1970: object["date"] as? TimeInterval ?? 0)
        )
    }
}
