import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import SwiftUI

class NotchViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    let inset: CGFloat

    init(inset: CGFloat = -4) {
        self.inset = inset
        super.init()
        setupCancellables()
    }

    deinit {
        destroy()
    }

    let animation: Animation = .interactiveSpring(
        duration: 0.5,
        extraBounce: 0.25,
        blendDuration: 0.125
    )
    /// The panel grows to fit the now playing row while a player is active.
    var notchOpenedSize: CGSize {
        guard let nowPlaying, panelTab == .music else {
            return .init(width: 600, height: 160)
        }
        return .init(width: 600, height: nowPlaying.hasProgress ? 244 : 216)
    }

    /// Tabs are only worth showing when there is a second thing to show.
    var showsPanelTabs: Bool { nowPlaying != nil }
    let dropDetectorRange: CGFloat = 32
    /// Width of the HUD panel on each side of the device notch. Kept tight so
    /// the transient overlay hides as little of the menu bar as possible.
    let hudSideWidth: CGFloat = 62
    let hudDismissDelay: TimeInterval = 1.6

    /// The now playing flash only needs room for artwork and a few bars.
    let mediaSideWidth: CGFloat = 34
    let mediaFlashDuration: TimeInterval = 2.5

    enum Status: String, Codable, Hashable, Equatable {
        case closed
        case opened
        case popping
    }

    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case unknown
    }

    enum PanelTab: Int, CaseIterable, Identifiable, Hashable {
        case files
        case music

        var id: Int { rawValue }
    }

    enum ContentType: Int, Codable, Hashable, Equatable {
        case normal
        case menu
        case settings
    }

    var notchOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - notchOpenedSize.height,
            width: notchOpenedSize.width,
            height: notchOpenedSize.height
        )
    }

    var headlineOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - deviceNotchRect.height,
            width: notchOpenedSize.width,
            height: deviceNotchRect.height
        )
    }

    /// Clicking the headline cycles the panel. Once tabs occupy its left half
    /// only the right half, where the menu glyph sits, keeps that behaviour.
    var headlineCycleRect: CGRect {
        guard showsPanelTabs else { return headlineOpenedRect }
        var rect = headlineOpenedRect
        rect.origin.x += rect.width / 2
        rect.size.width /= 2
        return rect
    }

    @Published private(set) var status: Status = .closed
    @Published var openReason: OpenReason = .unknown
    @Published var contentType: ContentType = .normal
    @Published var panelTab: PanelTab = .files

    @Published var spacing: CGFloat = 16
    @Published var cornerRadius: CGFloat = 16
    @Published var deviceNotchRect: CGRect = .zero
    @Published var screenRect: CGRect = .zero
    @Published var optionKeyPressed: Bool = false
    @Published var notchVisible: Bool = true
    @Published var hud: HUDPayload?
    @Published var nowPlaying: NowPlayingInfo?

    /// Shown briefly at the notch edges when the track or transport changes.
    @Published var showMediaFlash: Bool = false

    /// Music already playing at launch is not news, do not flash for it.
    var hasSeenNowPlaying: Bool = false

    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool

    let hapticSender = PassthroughSubject<Void, Never>()

    func notchOpen(_ reason: OpenReason) {
        hud = nil
        // A dragged file needs the tray, wherever the user left the tabs.
        if reason == .drag { panelTab = .files }
        openReason = reason
        status = .opened
        contentType = .normal
        NSApp.activate(ignoringOtherApps: true)
    }

    func notchClose() {
        openReason = .unknown
        status = .closed
        contentType = .normal
    }

    func showSettings() {
        contentType = .settings
    }

    func notchPop() {
        openReason = .unknown
        status = .popping
    }
}
