import AVFoundation
import Foundation
import ServiceManagement
import SwiftUI

final class AppModel: ObservableObject {

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Keys.volume) }
    }
    @Published var eventSounds: [SoundEvent: SoundChoice] {
        didSet { saveEventSounds() }
    }
    @Published var categoryEnabled: [SoundCategory: Bool] {
        didSet { saveCategoryEnabled() }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private let defaults = UserDefaults.standard
    private let lidMonitor = LidMonitor()
    private let usbWatcher = USBWatcher()
    private let displayWatcher = DisplayWatcher()
    private let audioWatcher = AudioWatcher()
    private let powerWatcher = PowerWatcher()

    private var players: [AVAudioPlayer] = []
    private weak var lidClosePlayer: AVAudioPlayer?
    private var lastClosePlay = Date.distantPast
    private var lastEventTime: [SoundEvent: Date] = [:]
    private var pendingPlays: [SoundCategory: DispatchWorkItem] = [:]
    private var lastCategoryPlay: [SoundCategory: Date] = [:]

    // One physical plug (USB-C monitor, dock, headset) raises events in several
    // categories at once; the most specific category wins. A category listed
    // here stays silent when any of its suppressors sounded recently.
    private static let suppressedBy: [SoundCategory: Set<SoundCategory>] = [
        .usb: [.displays, .audio, .charging],
        .audio: [.displays],
    ]
    // Suppressible categories wait this long before playing, in case a
    // higher-priority event for the same plug is still on its way. Display
    // handshakes can take a couple of seconds after USB enumeration.
    private static let holdWindow: [SoundCategory: TimeInterval] = [
        .usb: 2.5,
        .audio: 1.0,
    ]
    private static let suppressionWindow: TimeInterval = 6.0

    private enum Keys {
        static let enabled = "enabled"
        static let volume = "volume"
        static let eventSounds = "eventSounds"
        static let categoryEnabled = "categoryEnabled"
        // Pre-1.1 lid-only keys, migrated on first launch of this version.
        static let legacyOpenSound = "openSound"
        static let legacyCloseSound = "closeSound"
    }

    init() {
        defaults.register(defaults: [Keys.enabled: true, Keys.volume: 0.8])
        enabled = defaults.bool(forKey: Keys.enabled)
        volume = defaults.double(forKey: Keys.volume)
        eventSounds = Self.loadEventSounds(defaults)
        categoryEnabled = Self.loadCategoryEnabled(defaults)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func sound(for event: SoundEvent) -> SoundChoice {
        eventSounds[event] ?? event.defaultSound
    }

    func soundBinding(for event: SoundEvent) -> Binding<SoundChoice> {
        Binding(
            get: { self.sound(for: event) },
            set: { self.eventSounds[event] = $0 })
    }

    func enabledBinding(for category: SoundCategory) -> Binding<Bool> {
        Binding(
            get: { self.categoryEnabled[category] ?? true },
            set: { self.categoryEnabled[category] = $0 })
    }

    // MARK: - Event handling

    func start() {
        lidMonitor.onLidChange = { [weak self] closed in
            self?.handle(closed ? .lidClose : .lidOpen)
        }
        lidMonitor.sleepDelayProvider = { [weak self] in
            guard let self, let player = self.lidClosePlayer, player.isPlaying,
                  Date().timeIntervalSince(self.lastClosePlay) < 3
            else { return 0 }
            return player.duration - player.currentTime + 0.2
        }
        lidMonitor.start()

        usbWatcher.onEvent = { [weak self] plugged in
            self?.handle(plugged ? .usbPlug : .usbUnplug)
        }
        usbWatcher.start()

        displayWatcher.onEvent = { [weak self] connected in
            self?.handle(connected ? .displayConnect : .displayDisconnect)
        }
        displayWatcher.start()

        audioWatcher.onEvent = { [weak self] connected in
            self?.handle(connected ? .audioConnect : .audioDisconnect)
        }
        audioWatcher.start()

        powerWatcher.onEvent = { [weak self] event in
            switch event {
            case .chargeConnect: self?.handle(.chargeConnect)
            case .chargeDisconnect: self?.handle(.chargeDisconnect)
            case .chargeFull: self?.handle(.chargeFull)
            case .batteryLow: self?.handle(.batteryLow)
            }
        }
        powerWatcher.start()
    }

    private func handle(_ event: SoundEvent) {
        guard enabled, categoryEnabled[event.category] ?? true else { return }

        // Debounce: hubs/docks fire bursts of events; keep extending the window
        // while suppressed events keep arriving so a burst plays one sound total.
        let now = Date()
        if let last = lastEventTime[event], now.timeIntervalSince(last) < event.debounceWindow {
            lastEventTime[event] = now
            return
        }
        lastEventTime[event] = now

        let category = event.category

        // This event supersedes any lower-priority sound still waiting to play.
        for (other, suppressors) in Self.suppressedBy where suppressors.contains(category) {
            pendingPlays[other]?.cancel()
            pendingPlays[other] = nil
        }

        guard let hold = Self.holdWindow[category] else {
            fire(event)
            return
        }
        pendingPlays[category]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPlays[category] = nil
            let suppressors = Self.suppressedBy[category] ?? []
            let superseded = suppressors.contains {
                Date().timeIntervalSince(self.lastCategoryPlay[$0] ?? .distantPast)
                    < Self.suppressionWindow
            }
            if !superseded { self.fire(event) }
        }
        pendingPlays[category] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: item)
    }

    private func fire(_ event: SoundEvent) {
        lastCategoryPlay[event.category] = Date()
        if event == .lidClose { lastClosePlay = Date() }
        play(sound(for: event), holdsSleep: event == .lidClose)
    }

    func play(_ choice: SoundChoice, holdsSleep: Bool = false) {
        guard let url = choice.url else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(volume)
            player.play()
            players.removeAll { !$0.isPlaying }
            players.append(player)
            if holdsSleep { lidClosePlayer = player }
        } catch {
            NSLog("Snoopy: failed to play \(url.path): \(error)")
        }
    }

    // MARK: - Custom file picker

    func chooseCustomFile(completion: @escaping (SoundChoice?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound file"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(SoundChoice(kind: .custom, value: url.path))
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Snoopy: launch-at-login change failed: \(error)")
            // Registration only works from a proper .app bundle (not `swift run`).
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Persistence

    private func saveEventSounds() {
        let raw = Dictionary(uniqueKeysWithValues: eventSounds.map { ($0.rawValue, $1) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.eventSounds)
        }
    }

    private func saveCategoryEnabled() {
        let raw = Dictionary(uniqueKeysWithValues: categoryEnabled.map { ($0.rawValue, $1) })
        defaults.set(raw, forKey: Keys.categoryEnabled)
    }

    private static func loadEventSounds(_ defaults: UserDefaults) -> [SoundEvent: SoundChoice] {
        if let data = defaults.data(forKey: Keys.eventSounds),
           let raw = try? JSONDecoder().decode([String: SoundChoice].self, from: data) {
            var sounds: [SoundEvent: SoundChoice] = [:]
            for (key, choice) in raw {
                if let event = SoundEvent(rawValue: key) { sounds[event] = choice }
            }
            return sounds
        }
        // Migrate pre-1.1 lid-only settings.
        var sounds: [SoundEvent: SoundChoice] = [:]
        if let data = defaults.data(forKey: Keys.legacyOpenSound),
           let choice = try? JSONDecoder().decode(SoundChoice.self, from: data) {
            sounds[.lidOpen] = choice
        }
        if let data = defaults.data(forKey: Keys.legacyCloseSound),
           let choice = try? JSONDecoder().decode(SoundChoice.self, from: data) {
            sounds[.lidClose] = choice
        }
        return sounds
    }

    private static func loadCategoryEnabled(_ defaults: UserDefaults) -> [SoundCategory: Bool] {
        let raw = defaults.dictionary(forKey: Keys.categoryEnabled) as? [String: Bool] ?? [:]
        var result: [SoundCategory: Bool] = [:]
        for (key, value) in raw {
            if let category = SoundCategory(rawValue: key) { result[category] = value }
        }
        return result
    }
}
