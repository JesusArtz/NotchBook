//
//  NotchTimer.swift
//  NotchDrop
//
//  A countdown the user starts, kept visible at the notch while it runs.
//

import AppKit
import Combine
import Foundation

struct TimerSnapshot: Equatable {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    let phase: Phase
    let endDate: Date?
    let remainingWhenPaused: TimeInterval
    let configuredDuration: TimeInterval

    static let idle = TimerSnapshot(
        phase: .idle,
        endDate: nil,
        remainingWhenPaused: 0,
        configuredDuration: 5 * 60
    )

    /// Idle is the only phase with nothing worth showing at the notch.
    var isActive: Bool { phase != .idle }

    /// Derived from the end date rather than counted down, so it stays true
    /// across sleep, missed ticks and a busy run loop.
    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .running: max(endDate?.timeIntervalSince(date) ?? 0, 0)
        case .paused: remainingWhenPaused
        case .finished: 0
        case .idle: configuredDuration
        }
    }
}

class NotchTimerModel {
    static let shared = NotchTimerModel()

    let snapshot: CurrentValueSubject<TimerSnapshot, Never> = .init(.idle)

    /// Presets, in minutes. Twenty five is a pomodoro.
    let presets: [Int] = [1, 5, 10, 15, 25, 60]

    private var tick: Timer?
    private let tickInterval: TimeInterval = 0.25

    /// A finished timer stops shouting on its own.
    private let finishedLinger: TimeInterval = 30
    private var finishedAt: Date?

    private init() {
        let tick = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(tick, forMode: .common)
        self.tick = tick
    }

    deinit {
        destroy()
    }

    func destroy() {
        tick?.invalidate()
        tick = nil
    }

    // MARK: - Controls

    func setDuration(_ duration: TimeInterval) {
        let current = snapshot.value
        guard current.phase == .idle else { return }
        snapshot.send(.init(
            phase: .idle,
            endDate: nil,
            remainingWhenPaused: 0,
            configuredDuration: duration
        ))
    }

    func start() {
        let duration = snapshot.value.configuredDuration
        guard duration > 0 else { return }
        finishedAt = nil
        snapshot.send(.init(
            phase: .running,
            endDate: Date().addingTimeInterval(duration),
            remainingWhenPaused: 0,
            configuredDuration: duration
        ))
    }

    func pause() {
        let current = snapshot.value
        guard current.phase == .running else { return }
        snapshot.send(.init(
            phase: .paused,
            endDate: nil,
            remainingWhenPaused: current.remaining(at: Date()),
            configuredDuration: current.configuredDuration
        ))
    }

    func resume() {
        let current = snapshot.value
        guard current.phase == .paused else { return }
        snapshot.send(.init(
            phase: .running,
            endDate: Date().addingTimeInterval(current.remainingWhenPaused),
            remainingWhenPaused: 0,
            configuredDuration: current.configuredDuration
        ))
    }

    func reset() {
        finishedAt = nil
        snapshot.send(.init(
            phase: .idle,
            endDate: nil,
            remainingWhenPaused: 0,
            configuredDuration: snapshot.value.configuredDuration
        ))
    }

    // MARK: - Ticking

    private func step() {
        let current = snapshot.value
        switch current.phase {
        case .running:
            guard current.remaining(at: Date()) <= 0 else { return }
            finish(current)
        case .finished:
            guard let finishedAt, Date().timeIntervalSince(finishedAt) >= finishedLinger else { return }
            reset()
        case .idle, .paused:
            break
        }
    }

    private func finish(_ current: TimerSnapshot) {
        finishedAt = Date()
        snapshot.send(.init(
            phase: .finished,
            endDate: nil,
            remainingWhenPaused: 0,
            configuredDuration: current.configuredDuration
        ))
        NSSound(named: .init("Glass"))?.play()
    }
}
