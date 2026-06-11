import Foundation
import IOKit
import IOKit.pwr_mgt

/// Watches the MacBook's clamshell (lid) state via IOKit and reports open/close
/// transitions. Also hooks into the system sleep pipeline so a caller can delay
/// sleep briefly (e.g. to let a "lid closed" sound finish playing).
final class LidMonitor {

    /// Called on the main thread whenever the lid state changes. `true` = closed.
    var onLidChange: ((Bool) -> Void)?

    /// Asked when the system is about to sleep; return how many seconds to hold
    /// off sleep (clamped to 5s). Return 0 to allow sleep immediately.
    var sleepDelayProvider: (() -> TimeInterval)?

    /// Called when the system is about to sleep because the lid closed, in case
    /// the close event raced ahead of the clamshell notification.
    var onWillSleepWithLidClosed: (() -> Void)?

    private(set) var lidClosed = false

    // IOMessage.h constants are C macros, not imported into Swift.
    private static let messageClamshellStateChange: UInt32 = 0xE003_4100 // kIOPMMessageClamshellStateChange
    private static let messageSystemWillSleep: UInt32 = 0xE000_0280      // kIOMessageSystemWillSleep
    private static let messageCanSystemSleep: UInt32 = 0xE000_0270      // kIOMessageCanSystemSleep
    private static let messageSystemHasPoweredOn: UInt32 = 0xE000_0300  // kIOMessageSystemHasPoweredOn

    private var rootDomain: io_service_t = 0
    private var powerConnection: io_connect_t = 0
    private var powerNotifyPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var interestNotifyPort: IONotificationPortRef?
    private var interestNotifier: io_object_t = 0

    func start() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        lidClosed = readClamshellState() ?? false

        // 1. General-interest notification on IOPMrootDomain → clamshell changes.
        if rootDomain != 0 {
            interestNotifyPort = IONotificationPortCreate(kIOMainPortDefault)
            if let port = interestNotifyPort {
                let result = IOServiceAddInterestNotification(
                    port, rootDomain, kIOGeneralInterest,
                    { refcon, _, messageType, _ in
                        guard let refcon else { return }
                        let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                        monitor.handleInterest(messageType: messageType)
                    },
                    selfPtr, &interestNotifier)
                if result == KERN_SUCCESS {
                    CFRunLoopAddSource(
                        CFRunLoopGetMain(),
                        IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                        .commonModes)
                } else {
                    NSLog("Snoopy: clamshell interest notification failed (\(result))")
                }
            }
        } else {
            NSLog("Snoopy: IOPMrootDomain not found — lid detection unavailable")
        }

        // 2. System power registration → lets us delay sleep while a sound plays.
        var notifyPort: IONotificationPortRef?
        powerConnection = IORegisterForSystemPower(
            selfPtr, &notifyPort,
            { refcon, _, messageType, messageArgument in
                guard let refcon else { return }
                let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handlePower(messageType: messageType, argument: messageArgument)
            },
            &powerNotifier)
        powerNotifyPort = notifyPort
        if powerConnection != 0, let port = notifyPort {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                .commonModes)
        }
    }

    private func readClamshellState() -> Bool? {
        guard rootDomain != 0,
              let value = IORegistryEntryCreateCFProperty(
                  rootDomain, "AppleClamshellState" as CFString,
                  kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? Int { return n != 0 }
        return nil
    }

    private func handleInterest(messageType: UInt32) {
        guard messageType == Self.messageClamshellStateChange,
              let closed = readClamshellState(),
              closed != lidClosed
        else { return }
        lidClosed = closed
        onLidChange?(closed)
    }

    private func handlePower(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        let notificationID = intptr_t(bitPattern: argument.map(UInt.init(bitPattern:)) ?? 0)
        switch messageType {
        case Self.messageCanSystemSleep:
            IOAllowPowerChange(powerConnection, notificationID)
        case Self.messageSystemWillSleep:
            // If the lid is closed, give the close sound a chance to start
            // (covers the race where willSleep arrives before the clamshell
            // notification) and hold sleep until it finishes.
            if readClamshellState() == true {
                if !lidClosed {
                    lidClosed = true
                    onLidChange?(true)
                }
                onWillSleepWithLidClosed?()
            }
            let delay = min(max(sleepDelayProvider?() ?? 0, 0), 5)
            if delay > 0.05 {
                let connection = powerConnection
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    IOAllowPowerChange(connection, notificationID)
                }
            } else {
                IOAllowPowerChange(powerConnection, notificationID)
            }
        case Self.messageSystemHasPoweredOn:
            // Re-sync in case the clamshell notification was missed during sleep.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let closed = self.readClamshellState(),
                      closed != self.lidClosed else { return }
                self.lidClosed = closed
                self.onLidChange?(closed)
            }
        default:
            break
        }
    }
}
