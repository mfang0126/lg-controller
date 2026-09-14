import AppKit
import ApplicationServices
import CoreGraphics

final class FocusScreenResolver {
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns the screen owning the largest area of the focused window.
    /// Accessibility window coordinates and `CGDisplayBounds` share the global Core Graphics space.
    func focusedScreen() -> NSScreen? {
        guard let windowFrame = focusedWindowFrame() else { return nil }

        return NSScreen.screens
            .compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
                guard let displayID = DisplayIdentity.displayID(for: screen) else {
                    return nil
                }
                let displayFrame = CGDisplayBounds(displayID)
                let intersection = displayFrame.intersection(windowFrame)
                guard !intersection.isNull else { return nil }
                let area = max(0, intersection.width) * max(0, intersection.height)
                return (screen, area)
            }
            .max { left, right in left.area < right.area }?.screen
    }

    func focusedDisplayIdentity() -> DisplayIdentity? {
        guard let screen = focusedScreen() else { return nil }
        return DisplayIdentity.from(screen: screen)
    }

    private func focusedWindowFrame() -> CGRect? {
        let systemElement = AXUIElementCreateSystemWide()
        var applicationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedApplicationAttribute as CFString,
            &applicationValue
        ) == .success,
        applicationValue != nil else {
            return nil
        }
        let application = applicationValue as! AXUIElement

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        windowValue != nil else {
            return nil
        }
        let window = windowValue as! AXUIElement

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        let position = point(from: positionValue),
        let size = size(from: sizeValue) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func point(from value: CFTypeRef) -> CGPoint? {
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(from value: CFTypeRef) -> CGSize? {
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
