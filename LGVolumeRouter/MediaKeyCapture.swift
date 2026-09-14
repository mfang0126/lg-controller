import AppKit
import CoreGraphics
import Foundation

enum MediaKeyAction {
    case volumeUp
    case volumeDown
    case mute
}

/// Installs a narrow global event tap for the three media-key actions this app can route.
/// The handler decides whether macOS receives an event; this class never assumes every media key should be consumed.
final class MediaKeyCapture {
    private enum KeyCode: Int {
        case volumeUp = 0
        case volumeDown = 1
        case mute = 7
    }

    private let handler: (MediaKeyAction) -> Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping (MediaKeyAction) -> Bool) {
        self.handler = handler
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1) << 14 // NX_SYSDEFINED; the enum is not exported by current SDKs
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: MediaKeyCapture.eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
    }

    private func action(for keyCode: Int) -> MediaKeyAction? {
        switch KeyCode(rawValue: keyCode) {
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .mute: return .mute
        case nil: return nil
        }
    }

    /// The handler decides consumption. Unsupported keys and unmatched displays retain macOS behavior.
    private func shouldConsume(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined else {
            return false
        }
        let rawData = UInt64(bitPattern: Int64(nsEvent.data1))
        let keyCode = Int((rawData >> 16) & 0xFFFF)
        let keyState = (rawData >> 8) & 0xFF
        let isKeyDown = keyState == 0xA
        guard isKeyDown, let action = action(for: keyCode) else {
            return false
        }

        let isRepeat = (rawData & 0x1) == 1
        if action == .mute && isRepeat {
            return false
        }
        return handler(action)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let capture = Unmanaged<MediaKeyCapture>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = capture.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14 else {
            return Unmanaged.passUnretained(event)
        }

        return capture.shouldConsume(event) ? nil : Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}
