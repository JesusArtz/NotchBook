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

    var body: some View {
        HStack {
            if vm.showsPanelTabs, vm.contentType == .normal {
                PanelTabBar(tabs: vm.availableTabs, selection: $vm.panelTab, animation: vm.animation)
            } else {
                title
            }
            Spacer()
            Image(systemName: "ellipsis")
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
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Text(title(for: tab))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background {
                        if tab == selection {
                            Capsule().foregroundStyle(.white.opacity(0.18))
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(animation) { selection = tab }
                    }
            }
        }
        .padding(3)
        .background(Capsule().foregroundStyle(.white.opacity(0.07)))
    }

    private func title(for tab: NotchViewModel.PanelTab) -> LocalizedStringKey {
        switch tab {
        case .files: "Files"
        case .music: "Music"
        case .mirror: "Mirror"
        case .timer: "Timer"
        }
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
