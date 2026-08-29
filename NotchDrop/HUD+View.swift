//
//  HUD+View.swift
//  NotchDrop
//
//  Compact volume and brightness readout drawn beside the device notch.
//

import SwiftUI

struct NotchHUDView: View {
    let payload: HUDPayload
    let notchWidth: CGFloat
    let sideWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.interpolate)
                .frame(width: sideWidth)

            // The camera housing lives here, keep it clear.
            Color.clear
                .frame(width: notchWidth)

            HUDProgressBar(value: payload.value)
                .padding(.trailing, 16)
                .frame(width: sideWidth)
        }
        .frame(maxHeight: .infinity)
    }

    private var iconName: String {
        switch payload.kind {
        case .brightness:
            payload.value < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if payload.muted || payload.value <= 0 {
                "speaker.slash.fill"
            } else if payload.value < 0.34 {
                "speaker.wave.1.fill"
            } else if payload.value < 0.67 {
                "speaker.wave.2.fill"
            } else {
                "speaker.wave.3.fill"
            }
        }
    }
}

struct HUDProgressBar: View {
    let value: Double

    private let height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .foregroundStyle(.white.opacity(0.25))
                Capsule()
                    .foregroundStyle(.white)
                    // Keep a visible nub at zero so the bar never disappears.
                    .frame(width: max(geometry.size.width * value, height))
            }
        }
        .frame(height: height)
    }
}

#Preview {
    VStack(spacing: 12) {
        NotchHUDView(
            payload: .init(kind: .volume, value: 0.4),
            notchWidth: 180,
            sideWidth: 90
        )
        NotchHUDView(
            payload: .init(kind: .brightness, value: 0.8),
            notchWidth: 180,
            sideWidth: 90
        )
    }
    .frame(width: 360, height: 80)
    .background(.black)
    .preferredColorScheme(.dark)
}
