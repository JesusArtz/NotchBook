//
//  HUD+Brightness.swift
//  NotchDrop
//
//  Reads built-in display brightness through DisplayServices.
//

import CoreGraphics
import Foundation

final class BrightnessReader {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?

    init() {
        // Resolved at runtime, the framework is private and cannot be linked.
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        handle = dlopen(path, RTLD_LAZY)
        if let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        } else {
            getBrightness = nil
        }
        assert(getBrightness != nil, "DisplayServicesGetBrightness unavailable, brightness HUD disabled")
    }

    var isAvailable: Bool { getBrightness != nil }

    func current() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(builtinDisplayID, &value) == 0 else { return nil }
        return min(max(value, 0), 1)
    }

    private var builtinDisplayID: CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return CGMainDisplayID()
        }
        return ids.first { CGDisplayIsBuiltin($0) == 1 } ?? CGMainDisplayID()
    }
}
