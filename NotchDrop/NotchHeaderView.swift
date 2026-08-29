//
//  NotchHeaderView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import ColorfulX
import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel

    private var showsTabs: Bool {
        vm.showsPanelTabs && vm.contentType == .normal
    }

    var body: some View {
        HStack {
            // The tabs sit opposite the menu glyph, and the notch splits them.
            if showsTabs {
                Image(systemName: "ellipsis")
            } else {
                title
            }
            Spacer()
            if showsTabs {
                PanelTabBar(tabs: vm.availableTabs, selection: $vm.panelTab, animation: vm.animation)
            } else {
                Image(systemName: "ellipsis")
            }
        }
        .animation(vm.animation, value: vm.contentType)
        .animation(vm.animation, value: vm.showsPanelTabs)
        .font(.system(.headline, design: .rounded))
    }

    private var title: some View {
        Group {
            Text(
                vm.contentType == .settings
                    ? "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))"
                    : "Notch Drop"
            )
            .contentTransition(.numericText())
        }
    }
}

/// Segmented switch between the file tray and the player.
struct PanelTabBar: View {
    let tabs: [NotchViewModel.PanelTab]
    @Binding var selection: NotchViewModel.PanelTab
    let animation: Animation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                Image(systemName: icon(for: tab))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 15, height: 15)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .opacity(tab == selection ? 1 : 0.55)
                    .background {
                        if tab == selection {
                            Capsule().foregroundStyle(.white.opacity(0.18))
                        }
                    }
                    .contentShape(Capsule())
                    // Icons alone are not self explanatory, name them on hover.
                    .help(title(for: tab))
                    .onTapGesture {
                        withAnimation(animation) { selection = tab }
                    }
            }
        }
    }

    private func icon(for tab: NotchViewModel.PanelTab) -> String {
        switch tab {
        case .files: "tray.full.fill"
        case .music: "music.note"
        case .mirror: "person.crop.square"
        case .timer: "timer"
        case .claude: "sparkles"
        }
    }

    private func title(for tab: NotchViewModel.PanelTab) -> String {
        switch tab {
        case .files: "Files"
        case .music: "Music"
        case .mirror: "Mirror"
        case .timer: "Timer"
        case .claude: "Claude"
        }
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
