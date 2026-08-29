//
//  PrivacyIndicator.swift
//  NotchDrop
//
//  Reports when any app is using the camera or the microphone.
//

import AppKit
import AudioToolbox
import Combine
import CoreAudio
import CoreMediaIO
import Foundation

struct PrivacyState: Equatable {
    let cameraInUse: Bool
    let micInUse: Bool

    static let idle = PrivacyState(cameraInUse: false, micInUse: false)

    var isActive: Bool { cameraInUse || micInUse }
}

class PrivacyMonitor {
    static let shared = PrivacyMonitor()

    let state: CurrentValueSubject<PrivacyState, Never> = .init(.idle)

    private var timer: Timer?
    private let pollInterval: TimeInterval = 1

    private init() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    deinit {
        destroy()
    }

    func destroy() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let next = PrivacyState(cameraInUse: isCameraInUse(), micInUse: isMicInUse())
        guard next != state.value else { return }
        state.send(next)
    }

    // MARK: - Camera

    private func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        .init(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    /// CoreMediaIO answers for every process, not just ours.
    private func isCameraInUse() -> Bool {
        var listAddress = cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &listAddress, 0, nil, &size
        ) == 0, size > 0 else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &listAddress, 0, nil, size, &used, &ids
        ) == 0 else { return false }

        return ids.contains { device in
            var runAddress = cmioAddress(
                CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
            )
            var running: UInt32 = 0
            var consumed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &runAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &consumed, &running
            )
            return status == 0 && running != 0
        }
    }

    // MARK: - Microphone

    private func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private func isMicInUse() -> Bool {
        var listAddress = audioAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size
        ) == noErr, size > 0 else { return false }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size, &objects
        ) == noErr else { return false }

        return objects.contains { object in
            guard isRunningInput(object), let pid = processID(object) else { return false }
            // corespeechd holds the mic open for "Hey Siri" and never lets go.
            // Only processes that are real apps count, which is what the system
            // indicator does too.
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != nil
            else { return false }
            return true
        }
    }

    private func isRunningInput(_ object: AudioObjectID) -> Bool {
        var propertyAddress = audioAddress(kAudioProcessPropertyIsRunningInput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private func processID(_ object: AudioObjectID) -> pid_t? {
        var propertyAddress = audioAddress(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }
}

import SwiftUI

/// Camera on one side, microphone on the other, in the system's own colours.
struct PrivacyAccessory: View {
    let state: PrivacyState
    let notchWidth: CGFloat
    let sideWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer()
                if state.cameraInUse {
                    icon("video.fill", tint: .green)
                }
            }
            .padding(.trailing, 7)
            .frame(width: sideWidth)

            // The camera housing lives here, keep it clear.
            Color.clear
                .frame(width: notchWidth)

            HStack {
                if state.micInUse {
                    icon("mic.fill", tint: .orange)
                }
                Spacer()
            }
            .padding(.leading, 7)
            .frame(width: sideWidth)
        }
        .frame(maxHeight: .infinity)
    }

    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
    }
}
