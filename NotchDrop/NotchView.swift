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

    var hudVisible: Bool {
        vm.status != .opened && vm.hud != nil
    }

    /// Now playing only flashes on a change, it never sits over the menu bar.
    var mediaVisible: Bool {
        vm.status != .opened && vm.hud == nil && vm.showMediaFlash && vm.nowPlaying != nil
    }

    /// Unlike the others this one persists, because it reports a live camera
    /// or microphone. The brief flashes still win while they are on screen.
    var privacyVisible: Bool {
        vm.status != .opened && vm.hud == nil && !mediaVisible && vm.privacy.isActive
    }

    var accessoryVisible: Bool {
        hudVisible || mediaVisible || privacyVisible
    }

    /// Each accessory needs a different amount of room beside the notch.
    var accessorySideWidth: CGFloat {
        if hudVisible { return vm.hudSideWidth }
        if mediaVisible { return vm.mediaSideWidth }
        return vm.privacySideWidth
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
                if hudVisible, let hud = vm.hud {
                    NotchHUDView(
                        payload: hud,
                        notchWidth: vm.deviceNotchRect.width,
                        sideWidth: vm.hudSideWidth
                    )
                    .frame(
                        width: vm.deviceNotchRect.width + vm.hudSideWidth * 2,
                        height: vm.deviceNotchRect.height
                    )
                }
            }
            .zIndex(2)
            .transition(.opacity.animation(vm.animation))
            Group {
                if mediaVisible, let info = vm.nowPlaying {
                    NowPlayingAccessory(
                        info: info,
                        notchWidth: vm.deviceNotchRect.width,
                        sideWidth: vm.mediaSideWidth
                    )
                    .frame(
                        width: vm.deviceNotchRect.width + vm.mediaSideWidth * 2,
                        height: vm.deviceNotchRect.height
                    )
                }
            }
            .zIndex(1)
            .transition(.opacity.animation(vm.animation))
            Group {
                if privacyVisible {
                    PrivacyAccessory(
                        state: vm.privacy,
                        notchWidth: vm.deviceNotchRect.width,
                        sideWidth: vm.privacySideWidth
                    )
                    .frame(
                        width: vm.deviceNotchRect.width + vm.privacySideWidth * 2,
                        height: vm.deviceNotchRect.height
                    )
                }
            }
            .zIndex(1)
            .transition(.opacity.animation(vm.animation))
        }
        .background(dragDetector)
        .animation(vm.animation, value: vm.status)
        .animation(vm.animation, value: vm.hud)
        .animation(vm.animation, value: vm.nowPlaying)
        .animation(vm.animation, value: vm.showMediaFlash)
        .animation(vm.animation, value: vm.privacy)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
