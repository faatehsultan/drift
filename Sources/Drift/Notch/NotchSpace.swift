import AppKit

// Private SkyLight / CoreGraphics calls (the same trick other notch apps use).
// A window placed in its own space with a very high absolute level stays put
// while you swipe between desktops and fullscreen apps, instead of blinking.
typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
func CGSSpaceCreate(_ cid: CGSConnectionID, _ flags: Int32, _ options: CFDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceSetAbsoluteLevel")
func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int32)

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSShowSpaces")
func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

final class NotchSpace {
    static let shared = NotchSpace()
    private let cid: CGSConnectionID
    private let space: CGSSpaceID

    private init() {
        cid = CGSMainConnectionID()
        space = CGSSpaceCreate(cid, 0x1, nil)
        CGSSpaceSetAbsoluteLevel(cid, space, Int32.max)
        CGSShowSpaces(cid, [NSNumber(value: space)] as CFArray)
    }

    func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        CGSAddWindowsToSpaces(cid, [NSNumber(value: window.windowNumber)] as CFArray,
                              [NSNumber(value: space)] as CFArray)
    }
}
