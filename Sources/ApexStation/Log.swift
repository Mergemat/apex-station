import os

/// `log stream --predicate 'subsystem == "dev.bomarov.ApexStation"'` to follow along.
enum Log {
    static let usb = Logger(subsystem: "dev.bomarov.ApexStation", category: "usb")
    static let settings = Logger(subsystem: "dev.bomarov.ApexStation", category: "settings")
    static let pad = Logger(subsystem: "dev.bomarov.ApexStation", category: "virtual-pad")
}
