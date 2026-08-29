//
//  ClaudeBridge+View.swift
//  NotchDrop
//
//  The Claude tab and its notch-edge indicators.
//

import SwiftUI

/// Shown while a hook waits for an answer, or briefly when a turn ends.
struct ClaudeAccessory: View {
    let event: ClaudeEvent
    let notchWidth: CGFloat
    let sideWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer()
                Image(systemName: event.kind == .permission ? "hand.raised.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.kind == .permission ? .yellow : .green)
            }
            .padding(.trailing, 7)
            .frame(width: sideWidth)

            // The camera housing lives here, keep it clear.
            Color.clear
                .frame(width: notchWidth)

            HStack {
                Text(event.project)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.leading, 7)
            .frame(width: sideWidth)
        }
        .frame(maxHeight: .infinity)
    }
}

struct ClaudeBridgeView: View {
    @State private var state: ClaudeBridgeState = ClaudeBridge.shared.state.value

    private let bridge = ClaudeBridge.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pending = state.pending {
                permissionCard(pending)
            } else {
                history
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(bridge.state) { state = $0 }
    }

    private func permissionCard(_ event: ClaudeEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.yellow)
                Text(event.toolName.isEmpty ? "Permission" : event.toolName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(event.project)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Never approve what you cannot read, so the command is shown whole.
            ScrollView(.vertical, showsIndicators: false) {
                Text(event.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 76)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).foregroundStyle(.white.opacity(0.08)))

            HStack(spacing: 8) {
                ClaudeButton(title: "Allow", icon: "checkmark", tint: .green) {
                    bridge.allow(event)
                }
                ClaudeButton(title: "Deny", icon: "xmark", tint: .red) {
                    bridge.deny(event)
                }
                ClaudeButton(title: "Ask in terminal", icon: "terminal", tint: .white) {
                    bridge.defer_(event)
                }
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        if state.recent.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 20))
                Text("No Claude activity yet")
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(state.recent) { event in
                        HStack(spacing: 7) {
                            Image(systemName: event.kind == .permission
                                ? "hand.raised.fill" : "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(event.kind == .permission ? .yellow : .green)
                                .frame(width: 14)
                            Text(event.project)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                            Text(event.detail)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

private struct ClaudeButton: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(.caption, design: .rounded).weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background { Capsule().foregroundStyle(tint.opacity(0.22)) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint == .white ? .white : tint)
    }
}
