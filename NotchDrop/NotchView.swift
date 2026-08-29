//
//  NotchView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchView: View {
    @StateObject var vm: NotchViewModel

    @State var dropTargeting: Bool = false

    var notchSize: CGSize {
        if accessoryVisible {
            return .init(
                width: vm.deviceNotchRect.width + accessorySideWidth * 2,
                height: vm.deviceNotchRect.height
            )
        }
        switch vm.status {
        case .closed:
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4,
                height: vm.deviceNotchRect.height - 4
            )
            if ans.width < 0 { ans.width = 0 }
            if ans.height < 0 { ans.height = 0 }
            return ans
        case .opened:
            return vm.notchOpenedSize
        case .popping:
            return .init(
                width: vm.deviceNotchRect.width,
                height: vm.deviceNotchRect.height + 4
            )
        }
    }

    /// One band, many claimants. Ordered by urgency first, then by whether
    /// the user asked to see it at all.
    enum Accessory: Equatable {
        case none
        case hud
        case claudePermission
        case media
        case claudeFinished
        case timer
        case privacy
    }

    var accessory: Accessory {
        guard vm.status != .opened else { return .none }
        if vm.hud != nil { return .hud }
        // A blocked hook is waiting on an answer, nothing outranks that.
        if vm.claude.hasPending { return .claudePermission }
        if vm.showMediaFlash, vm.nowPlaying != nil { return .media }
        if vm.claude.finishedFlash != nil { return .claudeFinished }
        if vm.timer.isActive { return .timer }
        // The system reports a live camera on its own, so this yields to all.
        if vm.privacy.isActive { return .privacy }
        return .none
    }

    var accessoryVisible: Bool { accessory != .none }

    /// Each accessory needs a different amount of room beside the notch.
    var accessorySideWidth: CGFloat {
        switch accessory {
        case .hud: vm.hudSideWidth
        case .media: vm.mediaSideWidth
        case .timer: vm.timerSideWidth
        case .claudePermission, .claudeFinished: vm.claudeSideWidth
        case .privacy: vm.privacySideWidth
        case .none: 0
        }
    }

    var notchCornerRadius: CGFloat {
        guard !accessoryVisible else { return 10 }
        return switch vm.status {
        case .closed: 8
        case .opened: 32
        case .popping: 10
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notch
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible || accessoryVisible ? 1 : 0.3)
            Group {
                if vm.status == .opened {
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(vm.spacing)
                    .frame(maxWidth: vm.notchOpenedSize.width, maxHeight: vm.notchOpenedSize.height)
                    .zIndex(1)
                }
            }
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.notchOpenedSize.height / 2)
                ).animation(vm.animation)
            )
            Group {
                switch accessory {
                case .hud:
                    if let hud = vm.hud {
                        band { NotchHUDView(payload: hud, notchWidth: $0, sideWidth: $1) }
                    }
                case .media:
                    if let info = vm.nowPlaying {
                        band { NowPlayingAccessory(info: info, notchWidth: $0, sideWidth: $1) }
                    }
                case .claudePermission:
                    if let event = vm.claude.pending {
                        band { ClaudeAccessory(event: event, notchWidth: $0, sideWidth: $1) }
                    }
                case .claudeFinished:
                    if let event = vm.claude.finishedFlash {
                        band { ClaudeAccessory(event: event, notchWidth: $0, sideWidth: $1) }
                    }
                case .timer:
                    band { TimerAccessory(snapshot: vm.timer, notchWidth: $0, sideWidth: $1) }
                case .privacy:
                    band { PrivacyAccessory(state: vm.privacy, notchWidth: $0, sideWidth: $1) }
                case .none:
                    EmptyView()
                }
            }
            .zIndex(2)
            .transition(.opacity.animation(vm.animation))
        }
        .background(dragDetector)
        .animation(vm.animation, value: vm.status)
        .animation(vm.animation, value: vm.hud)
        .animation(vm.animation, value: vm.nowPlaying)
        .animation(vm.animation, value: vm.showMediaFlash)
        .animation(vm.animation, value: vm.privacy)
        .animation(vm.animation, value: vm.timer)
        .animation(vm.animation, value: vm.claude)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Every accessory occupies the same strip, straddling the notch.
    @ViewBuilder
    private func band<Content: View>(
        @ViewBuilder _ content: (CGFloat, CGFloat) -> Content
    ) -> some View {
        content(vm.deviceNotchRect.width, accessorySideWidth)
            .frame(
                width: vm.deviceNotchRect.width + accessorySideWidth * 2,
                height: vm.deviceNotchRect.height
            )
    }

    var notch: some View {
        Rectangle()
            .foregroundStyle(.black)
            .mask(notchBackgroundMaskGroup)
            .frame(
                width: notchSize.width + notchCornerRadius * 2,
                height: notchSize.height
            )
            .shadow(
                color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 1 : 0),
                radius: 16
            )
    }

    var notchBackgroundMaskGroup: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(
                width: notchSize.width,
                height: notchSize.height
            )
            .clipShape(.rect(
                bottomLeadingRadius: notchCornerRadius,
                bottomTrailingRadius: notchCornerRadius
            ))
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topTrailingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -notchCornerRadius - vm.spacing + 0.5, y: -0.5)
            }
            .overlay {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topLeadingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: notchCornerRadius + vm.spacing - 0.5, y: -0.5)
            }
    }

    @ViewBuilder
    var dragDetector: some View {
        RoundedRectangle(cornerRadius: notchCornerRadius)
            .foregroundStyle(Color.black.opacity(0.001)) // fuck you apple and 0.001 is the smallest we can have
            .contentShape(Rectangle())
            .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { isTargeted in
                if isTargeted, vm.status == .closed {
                    // Open the notch when a file is dragged over it
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !isTargeted {
                    // Close the notch when the dragged item leaves the area
                    let mouseLocation: NSPoint = NSEvent.mouseLocation
                    if !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(mouseLocation) {
                        vm.notchClose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
