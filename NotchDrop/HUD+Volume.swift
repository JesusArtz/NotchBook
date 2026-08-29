//
//  HUD+Volume.swift
//  NotchDrop
//
//  Reads the default output device volume and reports changes from CoreAudio.
//

import AudioToolbox
import CoreAudio
import Foundation

final class VolumeReader {
    /// Called on the main queue with the current scalar volume and mute state.
    var onChange: ((Float, Bool) -> Void)?

    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var deviceListenerInstalled = false
    private var systemListenerInstalled = false

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self else { return }
        emitCurrentState()
    }

    private lazy var systemListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self else { return }
        // The user switched output devices, follow the new one silently.
        rebindDevice()
    }

    deinit {
        stop()
    }

    func start() {
        guard !systemListenerInstalled else { return }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            systemListener
        )
        systemListenerInstalled = status == noErr
        bindDevice()
    }

    func stop() {
        unbindDevice()
        guard systemListenerInstalled else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            systemListener
        )
        systemListenerInstalled = false
    }

    private func rebindDevice() {
        unbindDevice()
        bindDevice()
    }

    private func bindDevice() {
        guard let device = currentDefaultOutputDevice() else { return }
        deviceID = device

        let volumeStatus = AudioObjectAddPropertyListenerBlock(
            device,
            &volumeAddress,
            DispatchQueue.main,
            deviceListener
        )
        // Not every device exposes mute, a failure here is not fatal.
        AudioObjectAddPropertyListenerBlock(
            device,
            &muteAddress,
            DispatchQueue.main,
            deviceListener
        )
        deviceListenerInstalled = volumeStatus == noErr
    }

    private func unbindDevice() {
        guard deviceListenerInstalled, deviceID != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, deviceListener)
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, deviceListener)
        deviceListenerInstalled = false
        deviceID = kAudioObjectUnknown
    }

    private func emitCurrentState() {
        guard let volume = currentVolume() else { return }
        onChange?(volume, currentMute())
    }

    private func currentDefaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func currentVolume() -> Float? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func currentMute() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &value)
        guard status == noErr else { return false }
        return value != 0
    }
}
