import ApexKit
import AppKit
import SwiftUI

/// The controller's four on-board profiles and what every button does in each.
struct ButtonsPage: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var viewing: Int?

    var body: some View {
        VStack(spacing: 18) {
            if service.profiles.isEmpty {
                Card { Text(service.connected ? "Reading profiles…" : "Connect your Apex 5 to see its profiles.").foregroundStyle(Theme.secondary) }
            } else {
                profilePicker
                if let profile = shown { MappingCard(profile: profile, active: profile.slot == service.activeProfile) }
                backupNote
            }
        }
    }

    private var shown: Profile? {
        let slot = viewing ?? service.activeProfile ?? 0
        return service.profiles.first { $0.slot == slot }
    }

    private var profilePicker: some View {
        HStack(spacing: 12) {
            ForEach(service.profiles, id: \.slot) { p in
                let selected = p.slot == shown?.slot
                let active = p.slot == service.activeProfile
                Button { viewing = p.slot } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(p.slot + 1)").font(.system(size: 22, weight: .semibold, design: .rounded))
                            Spacer()
                            if active {
                                Text("ACTIVE").font(.system(size: 9, weight: .bold)).tracking(1.2)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Theme.accent, in: .capsule)
                            }
                        }
                        Text(displayName(p)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(p.remapped.isEmpty ? "Default buttons" : "\(p.remapped.count) remapped")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.label)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(.rect(cornerRadius: 18), tint: selected ? Theme.accent.opacity(0.35) : nil, interactive: true)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Theme.glow.opacity(0.7) : .clear, lineWidth: 1.2))
                    .bloom(active, radius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var backupNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(Theme.accent)
            Text("All profiles are backed up to your Mac before anything is changed.")
                .font(.system(size: 12)).foregroundStyle(Theme.label)
            Spacer()
            Button("Show backups") { NSWorkspace.shared.open(ProfileBackup.folder) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 6)
    }
}

/// Flydigi names new profiles "配置N" ("Config N").
func displayName(_ p: Profile) -> String {
    let name = p.name
    if name.isEmpty { return "Profile \(p.slot + 1)" }
    if name.hasPrefix("配置") { return "Config " + name.dropFirst(2) }
    return name
}

private struct MappingCard: View {
    @Environment(ControllerService.self) private var service
    let profile: Profile
    let active: Bool
    @ViewState private var switching = false

    private let groups: [(String, [FlydigiKey])] = [
        ("Face", [.a, .b, .x, .y]),
        ("D-pad", [.up, .down, .left, .right]),
        ("Shoulders", [.lb, .rb, .lt, .rt, .lm, .rm]),
        ("Back paddles", [.m1, .m2, .m3, .m4]),
        ("Sticks", [.l3, .r3]),
        ("System", [.view, .menu, .home]),
    ]

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Caption("Profile \(profile.slot + 1)")
                    Text(displayName(profile)).font(.system(size: 22, weight: .semibold))
                }
                Spacer()
                if active {
                    Label("In use", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 13, weight: .semibold))
                } else {
                    Button {
                        switching = true
                        Task { await service.useProfile(profile.slot); switching = false }
                    } label: {
                        Text(switching ? "Switching…" : "Make active")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .glass(.capsule, tint: Theme.accent.opacity(0.5), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(switching)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18, alignment: .top), GridItem(.flexible(), spacing: 18, alignment: .top),
                                GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.0) { title, keys in
                    VStack(alignment: .leading, spacing: 8) {
                        Caption(title)
                        ForEach(keys, id: \.self) { MappingRow(key: $0, profile: profile) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.top, 6)
        }
    }
}

private struct MappingRow: View {
    let key: FlydigiKey
    let profile: Profile

    var body: some View {
        let mapping = profile.mapping(for: key)
        let changed = mapping != .standard
        HStack(spacing: 8) {
            Text(key.name)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .frame(minWidth: 38)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: .capsule)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(changed ? Theme.accent : Theme.label)
            Text(describe(mapping))
                .font(.system(size: 12.5, weight: changed ? .semibold : .regular))
                .foregroundStyle(changed ? Color.white : Theme.label)
            if let t = profile.turbo(for: key) {
                Text("TURBO \(t.speed)").font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.35), in: .capsule)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(changed ? Theme.accent.opacity(0.14) : .clear, in: .rect(cornerRadius: 10))
    }

    private func describe(_ m: KeyMapping) -> String {
        switch m {
        case .standard: "Default"
        case .button(let k): k.name
        case .macro: "Macro"
        case .keyboardOrMouse: "Keyboard / mouse"
        case .unknown(let raw): "Code \(raw)"
        }
    }
}
