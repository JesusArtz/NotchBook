//
//  Mirror+View.swift
//  NotchDrop
//
//  A camera preview in the notch, running only while its tab is open.
//

import AVFoundation
import SwiftUI

final class MirrorModel: ObservableObject {
    enum State: Equatable {
        case idle
        case denied
        case running
        case unavailable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var selectedID: String?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "wiki.qaq.NotchDrop.mirror")

    /// Desk View is a downward crop of the same camera, useless as a mirror.
    private let excludedNameFragments = ["Desk View", "Vista del Escritorio"]

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.state = .denied
                    return
                }
                self.loadDevices()
                self.configureAndRun(preferred: self.selectedID)
            }
        }
    }

    /// The camera light must go out the moment the tab is left.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if session.isRunning { session.stopRunning() }
        }
        state = .idle
    }

    func select(_ device: AVCaptureDevice) {
        selectedID = device.uniqueID
        configureAndRun(preferred: device.uniqueID)
    }

    private func loadDevices() {
        // External and Continuity cameras only exist as device types on 14+.
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(contentsOf: [.external, .continuityCamera])
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices.filter { device in
            !excludedNameFragments.contains { device.localizedName.contains($0) }
        }
        if selectedID == nil {
            // The built-in camera is the one behind the notch, prefer it.
            selectedID = devices.first { $0.deviceType == .builtInWideAngleCamera }?.uniqueID
                ?? devices.first?.uniqueID
        }
    }

    private func configureAndRun(preferred: String?) {
        guard let device = devices.first(where: { $0.uniqueID == preferred }) ?? devices.first else {
            state = .unavailable
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.sessionPreset = .high
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }
}

struct MirrorView: View {
    @StateObject private var model = MirrorModel()

    var body: some View {
        VStack(spacing: 8) {
            preview
            if model.devices.count > 1 {
                cameraPicker
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .foregroundStyle(.white.opacity(0.08))
            switch model.state {
            case .running:
                CameraPreview(session: model.session)
                    .clipShape(.rect(cornerRadius: 12))
            case .denied:
                message("Camera access denied", icon: "video.slash.fill")
            case .unavailable:
                message("No camera found", icon: "video.slash.fill")
            case .idle:
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20))
            Text(text).font(.system(.caption, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    private var cameraPicker: some View {
        HStack(spacing: 6) {
            ForEach(model.devices, id: \.uniqueID) { device in
                Text(device.localizedName)
                    .font(.system(.caption2, design: .rounded))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().foregroundStyle(
                            device.uniqueID == model.selectedID
                                ? .white.opacity(0.22)
                                : .white.opacity(0.08)
                        )
                    }
                    .contentShape(Capsule())
                    .onTapGesture { model.select(device) }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        // Without this you raise your right hand and the left one moves.
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        view.layer = preview
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let preview = view.layer as? AVCaptureVideoPreviewLayer else { return }
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
    }
}
