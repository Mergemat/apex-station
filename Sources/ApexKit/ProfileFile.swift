import Foundation

/// A profile saved to a file, to share or keep: the 840-byte record and its lighting, as JSON.
public struct ProfileFile: Codable, Sendable, Equatable {
    public static let format = "apex-station-profile"
    public static let fileExtension = "apexprofile"

    public var format = Self.format
    public var version = 1
    public var name: String
    public var profile: Data
    public var lighting: Data?

    public init(profile: Profile, lighting: Lighting?, name: String) {
        self.name = name
        self.profile = Data(profile.bytes)
        self.lighting = lighting.map { Data($0.bytes) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads a file, or nil if it isn't a profile this app can write to the Apex 5.
    public static func decode(_ data: Data) -> ProfileFile? {
        guard let file = try? JSONDecoder().decode(ProfileFile.self, from: data),
              file.format == format, file.version == 1,
              Profile(slot: 0, bytes: [UInt8](file.profile)) != nil else { return nil }
        if let l = file.lighting, Lighting(slot: 0, bytes: [UInt8](l)) == nil { return nil }
        return file
    }

    /// The profile to write into `slot`.
    public func profile(for slot: Int) -> Profile? { Profile(slot: slot, bytes: [UInt8](profile)) }
    public func lighting(for slot: Int) -> Lighting? { lighting.flatMap { Lighting(slot: slot, bytes: [UInt8]($0)) } }
}
