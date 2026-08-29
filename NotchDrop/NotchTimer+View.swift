//
//  NotchTimer+View.swift
//  NotchDrop
//
//  The timer tab, and the live countdown shown beside the closed notch.
//

import SwiftUI

/// Live countdown at the notch edges, the reason the timer exists.
struct TimerAccessory: View {
    let snapshot: TimerSnapshot
    let notchWidth: CGFloat
    let sideWidth: CGFloat

    var body: some View {
        // A whole second is the smallest change this can show.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                HStack {
                    Spacer()
                    Image(systemName: snapshot.phase == .paused ? "pause.fill" : "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .padding(.trailing, 7)
                .frame(width: sideWidth)

                // The camera housing lives here, keep it clear.
                Color.clear
                    .frame(width: notchWidth)

                HStack {
                    Text(TimerFormat.clock(snapshot.remaining(at: context.date)))
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                    Spacer()
                }
                .padding(.leading, 7)
                .frame(width: sideWidth)
            }
            .opacity(opacity(at: context.date))
        }
        .frame(maxHeight: .infinity)
    }

    private var tint: Color {
        switch snapshot.phase {
        case .finished: .orange
        case .paused: .white.opacity(0.6)
        default: .white
        }
    }

    /// A finished timer blinks until it is acknowledged or times out.
    private func opacity(at date: Date) -> Double {
        guard snapshot.phase == .finished else { return 1 }
        return Int(date.timeIntervalSinceReferenceDate) % 2 == 0 ? 1 : 0.25
    }
}

struct NotchTimerView: View {
    @State private var snapshot: TimerSnapshot = NotchTimerModel.shared.snapshot.value

    private let model = NotchTimerModel.shared

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimerFormat.clock(snapshot.remaining(at: context.date)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(snapshot.phase == .finished ? .orange : .white)
            }

            if snapshot.phase == .idle {
                presets
            }

            controls
        }
        .onReceive(model.snapshot) { snapshot = $0 }
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach(model.presets, id: \.self) { minutes in
                let duration = TimeInterval(minutes * 60)
                Text("\(minutes)m")
                    .font(.system(.caption, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().foregroundStyle(
                            duration == snapshot.configuredDuration
                                ? .white.opacity(0.22)
                                : .white.opacity(0.08)
                        )
                    }
                    .contentShape(Capsule())
                    .onTapGesture { model.setDuration(duration) }
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            switch snapshot.phase {
            case .idle:
                TimerButton(title: "Start", icon: "play.fill", prominent: true) { model.start() }
            case .running:
                TimerButton(title: "Pause", icon: "pause.fill") { model.pause() }
                TimerButton(title: "Reset", icon: "arrow.counterclockwise") { model.reset() }
            case .paused:
                TimerButton(title: "Resume", icon: "play.fill", prominent: true) { model.resume() }
                TimerButton(title: "Reset", icon: "arrow.counterclockwise") { model.reset() }
            case .finished:
                TimerButton(title: "Done", icon: "checkmark", prominent: true) { model.reset() }
            }
        }
    }
}

private struct TimerButton: View {
    let title: LocalizedStringKey
    let icon: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                Capsule().foregroundStyle(.white.opacity(prominent ? 0.24 : 0.1))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

enum TimerFormat {
    /// Hours only appear once they exist, so short timers stay readable.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    NotchTimerView()
        .padding()
        .frame(width: 560, height: 200)
        .background(.black)
        .preferredColorScheme(.dark)
}
