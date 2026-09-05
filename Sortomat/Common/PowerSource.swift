import Foundation
import IOKit.ps

/// Whether this Mac is currently running off its battery.
///
/// Sortomat's most expensive work — OCR, whole-file hashing, a paid model call
/// per file — used to happen at exactly the same rate whether the laptop was
/// plugged in at a desk or in a bag at 8 %. Nothing consulted the power source,
/// so a background tool designed to be forgotten drained the machine it was
/// forgotten on.
enum PowerSource {
    /// Fails open: a Mac with no battery (every desktop), or an IOKit answer we
    /// can't read, counts as plugged in. Refusing to work because a power query
    /// failed would be a worse bug than the one this prevents.
    static var isOnBattery: Bool {
        // Core Foundation's naming rule decides the accessor: `Copy` returns
        // +1 and is taken retained; `Get` does not, and claiming a reference
        // this code never acquired is an over-release. It happens not to crash
        // today only because IOKit hands back a constant string whose
        // retain/release are no-ops — an implementation detail, on a path that
        // runs on every pass.
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        else { return false }
        // `kIOPSBatteryPowerValue`. Spelled out because the macro's Swift name
        // has moved between SDKs and this file is compiled blind on CI.
        return type == "Battery Power"
    }

    static var isInLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
