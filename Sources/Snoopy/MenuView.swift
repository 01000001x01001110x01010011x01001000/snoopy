import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @State private var expandedCategory: SoundCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.enabled) {
                Text("Snoopy Sounds").font(.headline)
            }
            .toggleStyle(.switch)

            Divider()

            ForEach(SoundCategory.allCases, id: \.self) { category in
                categorySection(category)
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: $model.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func categorySection(_ category: SoundCategory) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(category)) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(category.events, id: \.self) { event in
                    soundRow(title: event.title, selection: model.soundBinding(for: event))
                }
            }
            .padding(.top, 6)
            .padding(.leading, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(category.title)
                Spacer()
                Toggle("", isOn: model.enabledBinding(for: category))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
    }

    /// Accordion behavior: opening one category collapses the others.
    private func expansionBinding(_ category: SoundCategory) -> Binding<Bool> {
        Binding(
            get: { expandedCategory == category },
            set: { expandedCategory = $0 ? category : nil })
    }

    @ViewBuilder
    private func soundRow(title: String, selection: Binding<SoundChoice>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.callout)
            Spacer()
            Menu {
                Button("None") { selection.wrappedValue = .none }
                Section("Presets") {
                    ForEach(SoundLibrary.presets, id: \.id) { preset in
                        Button(preset.name) {
                            selection.wrappedValue = SoundChoice(kind: .preset, value: preset.id)
                        }
                    }
                }
                Section("System Sounds") {
                    ForEach(SoundLibrary.systemSoundNames, id: \.self) { name in
                        Button(name) {
                            selection.wrappedValue = SoundChoice(kind: .system, value: name)
                        }
                    }
                }
                Section {
                    Button("Choose File…") {
                        model.chooseCustomFile { choice in
                            if let choice { selection.wrappedValue = choice }
                        }
                    }
                }
            } label: {
                Text(selection.wrappedValue.displayName)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 130)

            Button {
                model.play(selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview")
            .disabled(selection.wrappedValue.kind == .none)
        }
    }
}
