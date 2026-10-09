import ApexKit
import CoreHID
import Foundation

/// The system-wide controller games see: a virtual Xbox Wireless Controller fed by Apex Station.
/// Rumble requests from games come back through the delegate.
final class VirtualXboxController: HIDVirtualDeviceDelegate, Sendable {
    private let device: HIDVirtualDevice
    private let onRumble: @Sendable (XboxWirelessReport.Rumble) -> Void
    private let reports: AsyncStream<Data>.Continuation

    /// nil if macOS refuses to create virtual HID devices for this app.
    init?(onRumble: @escaping @Sendable (XboxWirelessReport.Rumble) -> Void) {
        let properties = HIDVirtualDevice.Properties(
            descriptor: XboxWirelessReport.descriptor,
            vendorID: XboxWirelessReport.vendorID,
            productID: XboxWirelessReport.productID,
            transport: .bluetooth,
            product: "Xbox Wireless Controller",
            manufacturer: "Microsoft",
            versionNumber: 0,
            serialNumber: "apex-station"
        )
        guard let device = HIDVirtualDevice(properties: properties) else { return nil }
        self.device = device
        self.onRumble = onRumble
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(8))
        reports = continuation
        Task { [device] in
            await device.activate(delegate: self)
            // One consumer keeps reports in order.
            for await report in stream {
                try? await device.dispatchInputReport(data: report, timestamp: .now)
            }
        }
    }

    /// Sends one Xbox input report, as `XboxWirelessReport.encode` makes it.
    func send(report: Data) {
        reports.yield(report)
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType, id: HIDReportID?, data: Data) async throws {
        guard type == .output, id?.rawValue ?? XboxWirelessReport.rumbleReportID == XboxWirelessReport.rumbleReportID,
              let rumble = XboxWirelessReport.decodeRumble(data) else { return }
        onRumble(rumble)
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType, id: HIDReportID?, maxSize: Int) async throws -> Data {
        throw HIDDeviceError.unsupported
    }
}
