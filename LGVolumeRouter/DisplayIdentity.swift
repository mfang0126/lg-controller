import AppKit
import CoreGraphics
import Foundation

struct DisplayIdentity: Codable, Equatable, Hashable {
    let uuid: String?
    let vendor: UInt32?
    let model: UInt32?
    let serial: UInt32?
    let name: String

    init(
        uuid: String? = nil,
        vendor: UInt32? = nil,
        model: UInt32? = nil,
        serial: UInt32? = nil,
        name: String
    ) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.name = name
    }

    var hasStableIdentifier: Bool {
        uuid != nil || vendor != nil || model != nil || serial != nil
    }

    /// Matches UUID first, then the stable display fields, then the name fallback.
    func matches(_ current: DisplayIdentity) -> Bool {
        if let uuid {
            return current.uuid == uuid
        }

        if hasStableIdentifier {
            return vendor == current.vendor && model == current.model && serial == current.serial
        }

        return name == current.name
    }

    static func from(screen: NSScreen) -> DisplayIdentity {
        let name = screen.localizedName
        guard let displayID = displayID(for: screen) else {
            return DisplayIdentity(name: name)
        }

        let uuid: String?
        if let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            uuid = CFUUIDCreateString(kCFAllocatorDefault, displayUUID.takeUnretainedValue()) as String
        } else {
            uuid = nil
        }

        return DisplayIdentity(
            uuid: uuid,
            vendor: CGDisplayVendorNumber(displayID),
            model: CGDisplayModelNumber(displayID),
            serial: CGDisplaySerialNumber(displayID),
            name: name
        )
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[screenNumberKey] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    var stableDescription: String {
        if let uuid {
            return uuid
        }
        if hasStableIdentifier {
            return "\(vendor.map(String.init) ?? "-") / \(model.map(String.init) ?? "-") / \(serial.map(String.init) ?? "-")"
        }
        return "Name fallback"
    }
}
