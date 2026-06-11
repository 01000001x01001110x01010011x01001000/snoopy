import Foundation

/// A selectable sound: a bundled preset, a macOS system sound, a user file, or nothing.
struct SoundChoice: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case preset, system, custom, none
    }

    var kind: Kind
    var value: String // preset id / system sound name / custom file path

    static let none = SoundChoice(kind: .none, value: "")

    var displayName: String {
        switch kind {
        case .none: return "None"
        case .preset: return SoundLibrary.presets.first { $0.id == value }?.name ?? value
        case .system: return value
        case .custom: return (value as NSString).lastPathComponent
        }
    }

    var url: URL? {
        switch kind {
        case .none:
            return nil
        case .preset:
            return SoundLibrary.presetURL(id: value)
        case .system:
            return URL(fileURLWithPath: "/System/Library/Sounds/\(value).aiff")
        case .custom:
            return URL(fileURLWithPath: value)
        }
    }
}

enum SoundLibrary {
    struct Preset {
        let id: String   // file basename without extension
        let name: String
    }

    static let presets: [Preset] = [
        Preset(id: "shutter-open", name: "Shutter Open"),
        Preset(id: "shutter-close", name: "Shutter Close"),
        Preset(id: "camera-click", name: "Camera Click"),
        Preset(id: "soft-pop", name: "Soft Pop"),
        Preset(id: "plug-in", name: "Plug In"),
        Preset(id: "plug-out", name: "Plug Out"),
        Preset(id: "charge-up", name: "Charge Up"),
        Preset(id: "charge-full", name: "Charge Full"),
        Preset(id: "battery-low", name: "Battery Low"),
    ]

    static func presetURL(id: String) -> URL? {
        // Inside the assembled .app the WAVs live in Contents/Resources.
        if let url = Bundle.main.url(forResource: id, withExtension: "wav") {
            return url
        }
        // Dev fallback for `swift run`: Resources/Sounds next to the package root.
        let devPath = FileManager.default.currentDirectoryPath + "/Resources/Sounds/\(id).wav"
        if FileManager.default.fileExists(atPath: devPath) {
            return URL(fileURLWithPath: devPath)
        }
        return nil
    }

    /// Names of the built-in macOS alert sounds (Basso, Glass, Tink, …).
    static var systemSoundNames: [String] {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }
}
