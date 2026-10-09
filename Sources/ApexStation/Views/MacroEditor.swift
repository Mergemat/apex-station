import ApexKit
import SwiftUI

/// Builds the macro a button plays: record it on the controller or load one saved on this Mac,
/// adjust the gaps between steps, then save it to the profile.
struct MacroEditor: View {
    @Environment(ControllerService.self) private var service
    @Environment(Library.self) private var library
    let key: FlydigiKey
    let saved: Macro?
    /// Macros this profile can still take, counting this button's own.
    let slotsLeft: Int
    let onSaved: () -> Void

    @ViewState private var mode: Macro.Mode = .once
    @ViewState private var steps: [Macro.Step] = []
    @ViewState private var interval = Macro.defaultInterval
    @ViewState private var dirty = false
    @ViewState private var naming = false
    @ViewState private var name = ""

    private var recording: Bool { service.recordedSteps != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Plays")
            ChipPicker(options: Macro.Mode.allCases, selection: mode, label: label) { mode = $0; dirty = true }
            Text(detail(mode)).font(Theme.noteFont).foregroundStyle(Theme.label)
            if mode != .once {
                ValueSlider(title: "Pause between repeats", range: 0...250, unit: " ms", value: interval) { v in
                    interval = (v + 5) / 10 * 10
                    dirty = true
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caption("Steps")
                Spacer()
                if let last = shown.last {
                    Text(String(format: "%.2f s", Double(last.time) / 1000))
                        .font(Theme.monoFont).foregroundStyle(Theme.label)
                }
            }
            if recording {
                recordingBanner
            } else if steps.isEmpty {
                Note("Record the buttons you press on the controller.")
            } else {
                stepList
            }
            HStack(spacing: 8) {
                recordButton
                if !recording { libraryMenu }
            }
            if !service.canRead && !recording {
                Text("Recording needs Full controller, in settings.").font(Theme.noteFont).foregroundStyle(Theme.label)
            }
        }
        if !recording { footer }
    }

    /// While recording, the steps coming in; otherwise the draft.
    private var shown: [Macro.Step] { service.recordedSteps ?? steps }

    // MARK: - Steps

    private var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 10) {
                    Image(systemName: step.press ? "arrow.down.circle.fill" : "arrow.up.circle")
                        .font(Theme.bodyFont)
                        .foregroundStyle(step.press ? Theme.glow : Theme.label)
                    Text(step.key.shortName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .frame(minWidth: 30)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(step.press ? 0.1 : 0.04), in: .rect(cornerRadius: 6))
                    Text(step.press ? "press" : "release").font(Theme.detailFont).foregroundStyle(Theme.secondary)
                    Spacer()
                    if i == 0 {
                        Text("start").font(Theme.noteFont).foregroundStyle(Theme.label)
                    } else {
                        GapField(ms: gap(at: i)) { setGap($0, at: i) }
                    }
                    Button { remove(at: i) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.label)
                            .frame(width: 18, height: 18).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                if i < steps.count - 1 { Divider().overlay(Theme.stroke) }
            }
        }
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
    }

    private var recordingBanner: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 9, height: 9).bloom(true, radius: 6)
                .phaseAnimator([1.0, 0.35]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.6) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording").font(Theme.buttonFont)
                Text(shown.isEmpty ? "Press buttons on the controller…" : "\(shown.count) steps")
                    .font(Theme.detailFont).foregroundStyle(Theme.secondary).monospacedDigit()
            }
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.3)))
    }

    /// Macros saved on this Mac: save this one, or load a saved one into the editor.
    private var libraryMenu: some View {
        Menu {
            Button("Save to library…") { name = ""; naming = true }
                .disabled(steps.isEmpty)
            if !library.macros.isEmpty {
                Section("Load") {
                    ForEach(library.macros) { m in
                        Button("\(m.name) · \(m.macro.steps.count) steps") {
                            mode = m.macro.mode
                            steps = m.macro.steps
                            interval = m.macro.interval
                            dirty = true
                        }
                    }
                }
                Menu("Delete") {
                    ForEach(library.macros) { m in
                        Button(m.name, role: .destructive) { library.deleteMacro(m) }
                    }
                }
            }
        } label: {
            Label("Library", systemImage: "books.vertical")
                .font(Theme.buttonFont)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .glass(.capsule, interactive: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .alert("Save macro", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Save") { library.saveMacro(Macro(key: key, mode: mode, steps: steps, interval: interval), name: name) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var recordButton: some View {
        Button {
            if recording {
                Task {
                    let recorded = await service.stopRecording()
                    if !recorded.isEmpty { steps = recorded; dirty = true }
                }
            } else {
                service.startRecording()
            }
        } label: {
            Label(recording ? "Stop" : "Record", systemImage: recording ? "stop.fill" : "record.circle")
                .font(Theme.buttonFont)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .glass(.capsule, tint: recording ? Color.red.opacity(0.35) : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!service.canRead && !recording)
        .opacity(!service.canRead && !recording ? 0.4 : 1)
    }

    // MARK: - Save

    @ViewBuilder private var footer: some View {
        let canSave = !steps.isEmpty && (saved != nil || slotsLeft > 0) && dirty && !service.saving
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await service.setMacro(Macro(key: key, mode: mode, steps: steps, interval: interval))
                        dirty = false
                        onSaved()
                    }
                } label: {
                    Text(saved == nil ? "Save macro" : "Save changes")
                        .font(Theme.buttonFont)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(canSave ? Theme.accent : Color.white.opacity(0.06), in: .capsule)
                        .foregroundStyle(canSave ? .white : Theme.label)
                        .bloom(canSave, radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                if dirty, saved != nil {
                    Button("Undo") { load(saved) }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                }
            }
            if saved == nil && slotsLeft <= 0 {
                Text("This profile already has \(Profile.maxMacros) macros, the most it can hold.")
                    .font(Theme.noteFont).foregroundStyle(Theme.warning)
            } else {
                Text("\(slotsLeft) of \(Profile.maxMacros) macro slots free on this profile · \(steps.count)/\(Profile.maxMacroSteps) steps")
                    .font(Theme.noteFont).foregroundStyle(Theme.label)
            }
        }
        .onAppear { load(saved) }
        .onChange(of: saved) { _, new in if !dirty { load(new) } }
    }

    private func load(_ macro: Macro?) {
        mode = macro?.mode ?? .once
        steps = macro?.steps ?? []
        interval = macro?.interval ?? Macro.defaultInterval
        dirty = false
    }

    // MARK: - Editing

    private func gap(at i: Int) -> Int { steps[i].time - steps[i - 1].time }

    /// Changing a gap moves this step and everything after it.
    private func setGap(_ ms: Int, at i: Int) {
        let delta = max(0, ms) - gap(at: i)
        for j in i..<steps.count { steps[j].time += delta }
        dirty = true
    }

    private func remove(at i: Int) {
        let removedGap = i > 0 ? gap(at: i) : 0
        steps.remove(at: i)
        if i == 0, let first = steps.first?.time {
            for j in steps.indices { steps[j].time -= first }
        } else {
            for j in i..<steps.count { steps[j].time -= removedGap }
        }
        dirty = true
    }

    private func label(_ m: Macro.Mode) -> String {
        switch m {
        case .once: "Once"
        case .whileHeld: "While held"
        case .toggle: "Toggle"
        }
    }

    private func detail(_ m: Macro.Mode) -> String {
        switch m {
        case .once: "Each press plays the macro once."
        case .whileHeld: "Repeats for as long as you hold \(key.name)."
        case .toggle: "Press \(key.name) to start repeating, press again to stop."
        }
    }
}

/// The wait before a step, in milliseconds, editable in place. The controller keeps 10 ms steps.
private struct GapField: View {
    let ms: Int
    let commit: (Int) -> Void
    @ViewState private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text("+").foregroundStyle(Theme.label)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 42)
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, f in if !f { apply() } }
            Text("ms").foregroundStyle(Theme.label)
        }
        .font(Theme.monoFont)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.white.opacity(focused ? 0.1 : 0.05), in: .capsule)
        .onAppear { text = "\(ms)" }
        .onChange(of: ms) { _, new in text = "\(new)" }
    }

    private func apply() {
        guard let v = Int(text.trimmingCharacters(in: .whitespaces)) else { text = "\(ms)"; return }
        let rounded = min(60_000, max(0, (v + 5) / 10 * 10))
        text = "\(rounded)"
        if rounded != ms { commit(rounded) }
    }
}
