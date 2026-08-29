//
//  HUD.swift
//  NotchDrop
//
//  System volume and brightness monitoring for the notch HUD.
//

import Combine
import Foundation

enum HUDKind: Equatable {
    case volume
    case brightness
}

struct HUDPayload: Equatable {
    let kind: HUDKind
    let value: Double
    let muted: Bool

    init(kind: HUDKind, value: Double, muted: Bool = false) {
        self.kind = kind
        self.value = min(max(value, 0), 1)
        self.muted = muted
    }
}

class HUDMonitor {
    static let shared = HUDMonitor()

    let hudChange: PassthroughSubject<HUDPayload, Never> = .init()

    private let volume = VolumeReader()
    private let brightness = BrightnessReader()

    private var brightnessTimer: Timer?
    private var lastBrightness: Float?

    /// Brightness has no change notification, so we poll it. Ten hertz is fast
    /// enough to feel instant while staying far below a millisecond of work.
    private let brightnessPollInterval: TimeInterval = 0.1

    /// Ignore float jitter so a still display never emits a change.
    private let brightnessEpsilon: Float = 0.001

    private init() {
        volume.onChange = { [weak self] value, muted in
            guard let self else { return }
            hudChange.send(.init(kind: .volume, value: Double(value), muted: muted))
        }
        volume.start()

        lastBrightness = brightness.current()
        startBrightnessPolling()
    }

    deinit {
        destroy()
    }

    func destroy() {
        volume.stop()
        brightnessTimer?.invalidate()
        brightnessTimer = nil
    }

    private func startBrightnessPolling() {
        guard brightness.isAvailable else { return }
        let timer = Timer(timeInterval: brightnessPollInterval, repeats: true) { [weak self] _ in
            self?.pollBrightness()
        }
        // Common mode keeps the HUD alive while menus or resizes run the loop.
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
    }

    private func pollBrightness() {
        guard let value = brightness.current() else { return }
        defer { lastBrightness = value }
        guard let last = lastBrightness else { return }
        guard abs(value - last) > brightnessEpsilon else { return }
        hudChange.send(.init(kind: .brightness, value: Double(value)))
    }
}
