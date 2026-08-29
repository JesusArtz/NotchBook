//
//  NowPlaying+View.swift
//  NotchDrop
//
//  Collapsed artwork strip and the expanded transport controls.
//

import SwiftUI

/// Brief flash beside the device notch when the track or transport changes.
struct NowPlayingAccessory: View {
    let info: NowPlayingInfo
    let notchWidth: CGFloat
    let sideWidth: CGFloat

    private let artworkSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer()
                ArtworkView(info: info, size: artworkSize, cornerRadius: 5)
            }
            .padding(.trailing, 7)
            .frame(width: sideWidth)

            // The camera housing lives here, keep it clear.
            Color.clear
                .frame(width: notchWidth)

            HStack {
                EqualizerBars(isPlaying: info.isPlaying)
                Spacer()
            }
            .padding(.leading, 7)
            .frame(width: sideWidth)
        }
        .frame(maxHeight: .infinity)
    }
}

struct EqualizerBars: View {
    let isPlaying: Bool

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 13
    private let speed: Double = 6

    var body: some View {
        Group {
            if isPlaying {
                // Only animate while audio runs, an idle timeline wastes cycles.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    bars(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(at: nil)
            }
        }
        .frame(height: maxHeight)
    }

    private func bars(at time: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0 ..< barCount, id: \.self) { index in
                Capsule()
                    .foregroundStyle(.white)
                    .frame(width: barWidth, height: height(for: index, at: time))
            }
        }
    }

    private func height(for index: Int, at time: TimeInterval?) -> CGFloat {
        // Paused audio shows flat bars rather than a frozen waveform.
        guard let time else { return barWidth }
        // Offsetting each bar keeps them from pulsing in unison.
        let wave = abs(sin(time * speed + Double(index) * 0.8))
        return maxHeight * (0.25 + 0.75 * wave)
    }
}

/// Full row shown inside the opened panel.
struct NowPlayingControls: View {
    let info: NowPlayingInfo
    let onPrevious: () -> Void
    let onTogglePlay: () -> Void
    let onNext: () -> Void
    let onSeek: (TimeInterval) -> Void

    private let artworkSize: CGFloat = 40

    /// The artist when we have one, otherwise the app doing the playing.
    private var subtitle: String {
        info.artist.isEmpty ? (info.title.isEmpty ? "" : info.appName) : info.artist
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            // Generic players expose no timeline, so no bar is drawn for them.
            if info.hasProgress {
                ProgressScrubber(info: info, onSeek: onSeek)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(info: info, size: artworkSize, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title.isEmpty ? info.appName : info.title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                TransportButton(systemName: "backward.fill", action: onPrevious)
                TransportButton(
                    systemName: info.isPlaying ? "pause.fill" : "play.fill",
                    size: 18,
                    action: onTogglePlay
                )
                TransportButton(systemName: "forward.fill", action: onNext)
            }
        }
    }
}

struct ProgressScrubber: View {
    let info: NowPlayingInfo
    let onSeek: (TimeInterval) -> Void

    /// Set while dragging, so the bar follows the finger instead of the poll.
    @State private var dragFraction: Double?

    private let barHeight: CGFloat = 4
    private let rowHeight: CGFloat = 14

    var body: some View {
        Group {
            if info.isPlaying, dragFraction == nil {
                // Position is sampled once a second, glide between samples.
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    row(at: context.date)
                }
            } else {
                row(at: Date())
            }
        }
        .frame(height: rowHeight)
    }

    private func row(at date: Date) -> some View {
        let elapsed = dragFraction.map { $0 * info.duration } ?? info.elapsed(at: date)
        let fraction = info.duration > 0 ? elapsed / info.duration : 0
        return HStack(spacing: 8) {
            timeLabel(elapsed)
            bar(fraction: fraction)
            timeLabel(info.duration)
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> some View {
        Text(formatted(seconds))
            .font(.system(.caption2, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34)
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .foregroundStyle(.white.opacity(0.25))
                Capsule()
                    .foregroundStyle(.white)
                    .frame(width: max(width * fraction, barHeight))
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity)
            // The bar is thin, take the whole row as the grab area.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = clamped(value.location.x / width)
                    }
                    .onEnded { value in
                        let target = clamped(value.location.x / width)
                        dragFraction = nil
                        onSeek(target * info.duration)
                    }
            )
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct ArtworkView: View {
    let info: NowPlayingInfo
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let icon = info.appIcon {
                // No album art, the source app is the next best identity.
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .foregroundStyle(.white.opacity(0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.white.opacity(0.7))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

struct TransportButton: View {
    let systemName: String
    var size: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .contentTransition(.interpolate)
                .frame(width: size + 8, height: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NowPlayingControls(
        info: .init(
            title: "Some Song",
            artist: "Some Artist",
            album: "Some Album",
            artwork: nil,
            appIcon: nil,
            appName: "Spotify",
            bundleID: "com.spotify.client",
            isPlaying: true,
            isScriptable: true,
            position: 63,
            duration: 214,
            positionUpdatedAt: Date()
        ),
        onPrevious: {},
        onTogglePlay: {},
        onNext: {},
        onSeek: { _ in }
    )
    .padding()
    .frame(width: 560)
    .background(.black)
    .preferredColorScheme(.dark)
}
