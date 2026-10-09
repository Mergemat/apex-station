import ApexKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Profiles saved on this Mac: load one into a slot on the controller, save the slot's current
/// setup, or rename, duplicate, export and delete what's saved.
struct LibrarySheet: View {
    @Environment(ControllerService.self) private var service
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// The controller slot loading writes to.
    let slot: Int
    @ViewState private var renaming: Library.SavedProfile?
    @ViewState private var newName = ""
    @ViewState private var loaded: URL?
    @ViewState private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved profiles").font(Theme.titleFont)
                    Text("Load one into profile \(slot + 1) on the controller.").font(Theme.detailFont).foregroundStyle(Theme.label)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 8) {
                action("Save profile \(slot + 1)", icon: "square.and.arrow.down") {
                    if let file = service.exportProfile(slot) { library.save(file) }
                }
                .disabled(service.exportProfile(slot) == nil)
                action("Import file…", icon: "doc.badge.plus") { importFile() }
            }
            if let problem { Text(problem).font(Theme.noteFont).foregroundStyle(Theme.warning) }
            ScrollView {
                VStack(spacing: 8) {
                    if library.profiles.isEmpty {
                        Note("Nothing saved yet. Save a profile from the controller, or import a .\(ProfileFile.fileExtension) file.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(library.profiles) { p in row(p) }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .background(Theme.sheet)
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let p = renaming { library.rename(p, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ p: Library.SavedProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.file.name).font(Theme.headingFont)
                Text(summary(p)).font(Theme.noteFont).foregroundStyle(Theme.label)
            }
            Spacer()
            Button(loaded == p.url ? "Loaded" : "Load") {
                Task {
                    await service.importProfile(p.file, into: slot)
                    loaded = p.url
                }
            }
            .buttonStyle(.plain).font(Theme.buttonFont)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glass(.capsule, tint: Theme.accent.opacity(0.35), interactive: true)
            .disabled(!service.connected || service.saving)
            Menu {
                Button("Rename…") { renaming = p; newName = p.file.name }
                Button("Duplicate") { library.duplicate(p) }
                Button("Export…") { export(p) }
                Divider()
                Button("Delete", role: .destructive) { library.delete(p) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
    }

    private func summary(_ p: Library.SavedProfile) -> String {
        var parts = [p.modified.formatted(date: .abbreviated, time: .shortened)]
        if let profile = p.file.profile(for: 0) {
            if !profile.remapped.isEmpty { parts.append("\(profile.remapped.count) remapped") }
            if !profile.macros.isEmpty { parts.append("\(profile.macros.count) macro\(profile.macros.count == 1 ? "" : "s")") }
        }
        if p.file.lighting != nil { parts.append("with lighting") }
        return parts.joined(separator: " · ")
    }

    private func action(_ title: String, icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon).font(Theme.buttonFont)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .glass(.capsule, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var fileType: UTType { UTType(filenameExtension: ProfileFile.fileExtension) ?? .json }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let failed = panel.urls.filter { !library.importFile($0) }
        problem = failed.isEmpty ? nil : "Not Apex Station profiles: \(failed.map(\.lastPathComponent).joined(separator: ", "))"
    }

    private func export(_ p: Library.SavedProfile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        panel.nameFieldStringValue = p.url.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.copyItem(at: p.url, to: url)
    }
}
