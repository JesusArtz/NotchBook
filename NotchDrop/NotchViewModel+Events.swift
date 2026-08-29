//
//  NotchViewModel+Events.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Combine
import Foundation
import SwiftUI

extension NotchViewModel {
    func setupCancellables() {
        let events = EventMonitors.shared
        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let mouseLocation: NSPoint = NSEvent.mouseLocation
                switch status {
                case .opened:
                    // touch outside, close
                    if !notchOpenedRect.contains(mouseLocation) {
                        notchClose()
                        // click where user open the panel
                    } else if deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation) {
                        notchClose()
                        // for the same height as device notch, open the url of project
                    } else if headlineCycleRect.contains(mouseLocation) {
                        // for clicking headline which mouse event may handled by another app
                        // open the menu
                        if let nextValue = ContentType(rawValue: contentType.rawValue + 1) {
                            contentType = nextValue
                        } else {
                            contentType = ContentType(rawValue: 0)!
                        }
                    }
                case .closed, .popping:
                    // touch inside, open
                    if deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation) {
                        notchOpen(.click)
                    }
                }
            }
            .store(in: &cancellables)

        events.optionKeyPress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] input in
                guard let self else { return }
                optionKeyPressed = input
            }
            .store(in: &cancellables)

        events.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mouseLocation in
                guard let self else { return }
                let mouseLocation: NSPoint = NSEvent.mouseLocation
                let aboutToOpen = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation)
                if status == .closed, aboutToOpen { notchPop() }
                if status == .popping, !aboutToOpen { notchClose() }
            }
            .store(in: &cancellables)

        $status
            .filter { $0 != .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation { self?.notchVisible = true }
            }
            .store(in: &cancellables)

        $status
            .filter { $0 == .popping }
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.hapticSender.send()
            }
            .store(in: &cancellables)

        hapticSender
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard self?.hapticFeedback ?? false else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .now
                )
            }
            .store(in: &cancellables)

        $status
            .debounce(for: 0.5, scheduler: DispatchQueue.global())
            .filter { $0 == .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.notchVisible = false
                }
            }
            .store(in: &cancellables)

        HUDMonitor.shared.hudChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self else { return }
                // The opened panel owns the notch, do not fight it.
                guard status != .opened else { return }
                withAnimation(animation) { self.hud = payload }
            }
            .store(in: &cancellables)

        // Each new reading restarts the timer, so holding a key keeps it up.
        $hud
            .debounce(for: .seconds(hudDismissDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self, payload != nil else { return }
                withAnimation(animation) { self.hud = nil }
            }
            .store(in: &cancellables)

        NowPlayingMonitor.shared.info
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                let previous = nowPlaying
                withAnimation(animation) { self.nowPlaying = info }
                // Nothing playing means no music tab to sit on.
                if info == nil, panelTab == .music {
                    withAnimation(animation) { self.panelTab = .files }
                }

                let wasFirst = !hasSeenNowPlaying
                hasSeenNowPlaying = true
                guard let info else { return }
                // Whatever was already playing when we launched is not an event.
                guard !wasFirst else { return }

                let trackChanged = previous?.title != info.title
                    || previous?.artist != info.artist
                    || previous?.bundleID != info.bundleID
                let transportChanged = previous?.isPlaying != info.isPlaying
                guard trackChanged || transportChanged else { return }

                withAnimation(animation) { self.showMediaFlash = true }
            }
            .store(in: &cancellables)

        // Re-flashing restarts the timer, so a burst of skips stays on screen.
        $showMediaFlash
            .filter { $0 }
            .debounce(for: .seconds(mediaFlashDuration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                withAnimation(animation) { self.showMediaFlash = false }
            }
            .store(in: &cancellables)

        $selectedLanguage
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                self?.notchClose()
                output.apply()
            }
            .store(in: &cancellables)
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
