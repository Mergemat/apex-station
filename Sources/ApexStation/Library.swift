import ApexKit
import Foundation
import Observation

/// Profiles and macros saved on this Mac, in Application Support/Apex Station/Library: one
/// `.apexprofile` file per profile (the export format, so files can be dropped in or shared) and
/// the macros in macros.json.
@MainActor @Observable
final class Library {
    struct SavedProfile: Identifiable {
        let url: URL
        var file: ProfileFile
        var modified: Date
        var id: URL { url }
    }

    struct SavedMacro: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// The button it was saved from is ignored when it's used on another.
        var macro: Macro
        var saved = Date()
    }

    private(set) var profiles: [SavedProfile] = []
    private(set) var macros: [SavedMacro] = []

    private let folder = ProfileBackup.folder.deletingLastPathComponent().appendingPathComponent("Library", isDirectory: true)
    private var macrosFile: URL { folder.appendingPathComponent("macros.json") }

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        profiles = urls.filter { $0.pathExtension == ProfileFile.fileExtension }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let file = ProfileFile.decode(data) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return SavedProfile(url: url, file: file, modified: modified)
        }
        .sorted { $0.modified > $1.modified }
        macros = (try? JSONDecoder().decode([SavedMacro].self, from: Data(contentsOf: macrosFile))) ?? []
    }

    // MARK: Profiles

    func save(_ file: ProfileFile) {
        write(file, to: freshURL(for: file.name))
        reload()
    }

    func rename(_ p: SavedProfile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var file = p.file
        file.name = trimmed
        try? FileManager.default.removeItem(at: p.url)
        write(file, to: freshURL(for: trimmed))
        reload()
    }

    func duplicate(_ p: SavedProfile) {
        var file = p.file
        file.name += " copy"
        save(file)
    }

    func delete(_ p: SavedProfile) {
        try? FileManager.default.removeItem(at: p.url)
        reload()
    }

    /// Adds a profile file from elsewhere; false if it isn't one.
    func importFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let file = ProfileFile.decode(data) else { return false }
        save(file)
        return true
    }

    private func write(_ file: ProfileFile, to url: URL) {
        try? file.encoded().write(to: url)
    }

    /// A file name for `name` that isn't taken yet.
    private func freshURL(for name: String) -> URL {
        let base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var url = folder.appendingPathComponent("\(base).\(ProfileFile.fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).\(ProfileFile.fileExtension)")
            n += 1
        }
        return url
    }

    // MARK: Macros

    func saveMacro(_ macro: Macro, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        macros.insert(SavedMacro(name: trimmed.isEmpty ? "Macro" : trimmed, macro: macro), at: 0)
        writeMacros()
    }

    func renameMacro(_ m: SavedMacro, to name: String) {
        guard let i = macros.firstIndex(where: { $0.id == m.id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        macros[i].name = name.trimmingCharacters(in: .whitespaces)
        writeMacros()
    }

    func deleteMacro(_ m: SavedMacro) {
        macros.removeAll { $0.id == m.id }
        writeMacros()
    }

    private func writeMacros() {
        try? JSONEncoder().encode(macros).write(to: macrosFile)
    }
}
