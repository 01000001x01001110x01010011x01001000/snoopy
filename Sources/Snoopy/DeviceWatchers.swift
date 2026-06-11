import AppKit
import CoreAudio
import Foundation
import IOKit
import IOKit.ps

// MARK: - USB

/// Fires when a USB device is attached or detached on any port.
final class USBWatcher {
    var onEvent: ((_ plugged: Bool) -> Void)?

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var armed = false

    func start() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
            .commonModes)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<USBWatcher>.fromOpaque(refcon).takeUnretainedValue()
                .drain(iterator)
        }

        // kIOFirstMatchNotification / kIOTerminatedNotification (macros, not imported).
        IOServiceAddMatchingNotification(
            port, "IOServiceFirstMatch", IOServiceMatching("IOUSBHostDevice"),
            callback, selfPtr, &addedIterator)
        drain(addedIterator) // consume already-attached devices and arm the notification

        IOServiceAddMatchingNotification(
            port, "IOServiceTerminate", IOServiceMatching("IOUSBHostDevice"),
            callback, selfPtr, &removedIterator)
        drain(removedIterator)

        armed = true
    }

    private func drain(_ iterator: io_iterator_t) {
        var count = 0
        while case let obj = IOIteratorNext(iterator), obj != 0 {
            IOObjectRelease(obj)
            count += 1
        }
        guard armed, count > 0 else { return }
        onEvent?(iterator == addedIterator)
    }
}

// MARK: - Displays

/// Fires when an external display is connected or disconnected.
final class DisplayWatcher {
    var onEvent: ((_ connected: Bool) -> Void)?

    func start() {
        CGDisplayRegisterReconfigurationCallback(
            { display, flags, userInfo in
                guard let userInfo else { return }
                // The callback fires twice per change; skip the "before" pass.
                guard !flags.contains(.beginConfigurationFlag) else { return }
                // The built-in panel is "removed" on clamshell — that's the lid
                // sound's job, not a display event.
                guard CGDisplayIsBuiltin(display) == 0 else { return }
                let watcher = Unmanaged<DisplayWatcher>.fromOpaque(userInfo).takeUnretainedValue()
                if flags.contains(.addFlag) {
                    watcher.onEvent?(true)
                } else if flags.contains(.removeFlag) {
                    watcher.onEvent?(false)
                }
            },
            Unmanaged.passUnretained(self).toOpaque())
    }
}

// MARK: - Audio devices

/// Fires when an audio device appears/disappears (AirPods, USB audio, external
/// headphones) or the headphone jack switches the built-in output in place.
final class AudioWatcher {
    var onEvent: ((_ connected: Bool) -> Void)?

    private var knownDevices = Set<AudioDeviceID>()
    private var builtInOutputID: AudioDeviceID = 0
    private var lastDataSource: UInt32 = 0
    private static let headphonesSource: UInt32 = 0x6864_706E // 'hdpn'

    func start() {
        knownDevices = Self.allDevices()

        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, .main
        ) { [weak self] _, _ in
            guard let self else { return }
            let now = Self.allDevices()
            let added = !now.subtracting(self.knownDevices).isEmpty
            let removed = !self.knownDevices.subtracting(now).isEmpty
            self.knownDevices = now
            if added {
                self.onEvent?(true)
            } else if removed {
                self.onEvent?(false)
            }
        }

        setUpJackListener()
    }

    /// On some Macs the headphone jack doesn't add a device — it flips the
    /// built-in output's data source between speakers and headphones.
    private func setUpJackListener() {
        for id in knownDevices where Self.isBuiltInOutput(id) {
            builtInOutputID = id
            lastDataSource = Self.dataSource(of: id) ?? 0
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSource,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(id, &address, .main) { [weak self] _, _ in
                guard let self else { return }
                let source = Self.dataSource(of: self.builtInOutputID) ?? 0
                defer { self.lastDataSource = source }
                if source == Self.headphonesSource, self.lastDataSource != Self.headphonesSource {
                    self.onEvent?(true)
                } else if self.lastDataSource == Self.headphonesSource, source != Self.headphonesSource {
                    self.onEvent?(false)
                }
            }
            break
        }
    }

    private static func allDevices() -> Set<AudioDeviceID> {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return Set(ids)
    }

    private static func isBuiltInOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeBuiltIn
        else { return false }

        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamsSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &streamsSize) == noErr
            && streamsSize > 0
    }

    private static func dataSource(of id: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var source: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &source) == noErr
        else { return nil }
        return source
    }
}

// MARK: - Power / charging

/// Fires on charger plug/unplug, battery reaching 100%, and battery dropping
/// to 20% while on battery power.
final class PowerWatcher {
    enum Event {
        case chargeConnect, chargeDisconnect, chargeFull, batteryLow
    }

    var onEvent: ((Event) -> Void)?

    private var lastExternal: Bool?
    private var firedFull = false
    private var firedLow = false
    private var runLoopSource: CFRunLoopSource?

    func start() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue()
                    .refresh(notify: true)
            }, selfPtr)?.takeRetainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        refresh(notify: false)
    }

    private struct Snapshot {
        let external: Bool
        let percent: Int
        let isCharged: Bool
    }

    private func refresh(notify: Bool) {
        guard let snapshot = Self.read() else { return }

        if notify, let last = lastExternal, snapshot.external != last {
            onEvent?(snapshot.external ? .chargeConnect : .chargeDisconnect)
        }
        lastExternal = snapshot.external

        if snapshot.external {
            firedLow = false
            let full = snapshot.percent >= 100 && snapshot.isCharged
            if full && !firedFull && notify {
                onEvent?(.chargeFull)
            }
            firedFull = full || firedFull
            if !full && snapshot.percent < 100 { firedFull = false }
        } else {
            firedFull = false
            if snapshot.percent <= 20 {
                if !firedLow && notify { onEvent?(.batteryLow) }
                firedLow = true
            } else if snapshot.percent >= 25 {
                firedLow = false // re-arm once it recovers a bit
            }
        }
    }

    private static func read() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                desc["Type"] as? String == "InternalBattery" // kIOPSInternalBatteryType
            else { continue }
            let current = desc["Current Capacity"] as? Int ?? 0  // kIOPSCurrentCapacityKey
            let max = desc["Max Capacity"] as? Int ?? 100        // kIOPSMaxCapacityKey
            return Snapshot(
                external: desc["Power Source State"] as? String == "AC Power", // kIOPSPowerSourceStateKey
                percent: max > 0 ? current * 100 / max : current,
                isCharged: desc["Is Charged"] as? Bool ?? false) // kIOPSIsChargedKey
        }
        return nil // no battery (desktop) — nothing to report
    }
}
