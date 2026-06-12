import Foundation

/// Every distinct moment Snoopy can play a sound for.
enum SoundEvent: String, CaseIterable, Codable {
    case lidOpen, lidClose
    case screenUnlock, screenLock
    case usbPlug, usbUnplug
    case displayConnect, displayDisconnect
    case audioConnect, audioDisconnect
    case chargeConnect, chargeDisconnect, chargeFull, batteryLow

    var category: SoundCategory {
        switch self {
        case .lidOpen, .lidClose: return .lid
        case .screenUnlock, .screenLock: return .session
        case .usbPlug, .usbUnplug: return .usb
        case .displayConnect, .displayDisconnect: return .displays
        case .audioConnect, .audioDisconnect: return .audio
        case .chargeConnect, .chargeDisconnect, .chargeFull, .batteryLow: return .charging
        }
    }

    var title: String {
        switch self {
        case .lidOpen: return "Open"
        case .lidClose: return "Close"
        case .screenUnlock: return "Unlock"
        case .screenLock: return "Lock"
        case .usbPlug, .chargeConnect: return "Plug in"
        case .usbUnplug, .chargeDisconnect: return "Unplug"
        case .displayConnect, .audioConnect: return "Connect"
        case .displayDisconnect, .audioDisconnect: return "Disconnect"
        case .chargeFull: return "Fully charged"
        case .batteryLow: return "Low battery (20%)"
        }
    }

    var defaultSound: SoundChoice {
        switch self {
        case .lidOpen: return .none // unreliable at wake; unlock covers it
        case .lidClose: return SoundChoice(kind: .preset, value: "shutter-close")
        case .screenUnlock: return SoundChoice(kind: .preset, value: "shutter-open")
        case .screenLock: return .none
        case .usbPlug, .displayConnect: return SoundChoice(kind: .preset, value: "plug-in")
        case .usbUnplug, .displayDisconnect, .chargeDisconnect:
            return SoundChoice(kind: .preset, value: "plug-out")
        case .audioConnect, .audioDisconnect: return SoundChoice(kind: .preset, value: "soft-pop")
        case .chargeConnect: return SoundChoice(kind: .preset, value: "charge-up")
        case .chargeFull: return SoundChoice(kind: .preset, value: "charge-full")
        case .batteryLow: return SoundChoice(kind: .preset, value: "battery-low")
        }
    }

    /// Events from hubs/docks can arrive in bursts; collapse repeats inside this window.
    var debounceWindow: TimeInterval {
        switch category {
        case .usb, .displays, .audio: return 1.5
        case .lid, .session, .charging: return 1.0
        }
    }
}

/// A group of events sharing one enable toggle and one menu section.
enum SoundCategory: String, CaseIterable {
    case lid, session, usb, displays, audio, charging

    var title: String {
        switch self {
        case .lid: return "Lid"
        case .session: return "Lock & Unlock"
        case .usb: return "USB Devices"
        case .displays: return "Displays"
        case .audio: return "Audio Devices"
        case .charging: return "Charging"
        }
    }

    var icon: String {
        switch self {
        case .lid: return "laptopcomputer"
        case .session: return "lock.open"
        case .usb: return "cable.connector"
        case .displays: return "display"
        case .audio: return "headphones"
        case .charging: return "bolt.fill"
        }
    }

    var events: [SoundEvent] {
        SoundEvent.allCases.filter { $0.category == self }
    }
}
