//
//  NotchContentView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//  Last Modified by 冷月 on 2025/5/5.
//

import ColorfulX
import SwiftUI
import UniformTypeIdentifiers

struct NotchContentView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                Group {
                    switch vm.effectiveTab {
                    case .files:
                        HStack(spacing: vm.spacing) {
                            ShareView(vm: vm, type: .airdrop)
                            TrayView(vm: vm)
                        }
                    case .mirror:
                        MirrorView()
                    case .timer:
                        NotchTimerView()
                    case .claude:
                        ClaudeBridgeView()
                    case .music:
                        if let info = vm.nowPlaying {
                            NowPlayingControls(
                                info: info,
                                onPrevious: { NowPlayingMonitor.shared.previousTrack() },
                                onTogglePlay: { NowPlayingMonitor.shared.togglePlayPause() },
                                onNext: { NowPlayingMonitor.shared.nextTrack() },
                                onSeek: { NowPlayingMonitor.shared.seek(to: $0) }
                            )
                        }
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .menu:
                NotchMenuView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .settings:
                NotchSettingsView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(vm.animation, value: vm.contentType)
        .animation(vm.animation, value: vm.effectiveTab)
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
