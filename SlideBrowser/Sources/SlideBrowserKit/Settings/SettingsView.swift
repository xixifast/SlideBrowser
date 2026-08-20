import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var siteStore: SiteStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var favicons: FaviconService

    let onHotKeyChange: (HotKeyCombo) -> Void
    let onSideChange: (PanelSide) -> Void
    let onWidthChange: (CGFloat) -> Void
    let onAlwaysOnTopChange: () -> Void
    let onResetSize: () -> Void

    @State private var selectedTab = 0
    @State private var editorTarget: SiteEditorTarget?

    var body: some View {
        TabView(selection: $selectedTab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            keyboard.tabItem { Label("Keyboard", systemImage: "keyboard") }.tag(1)
            browser.tabItem { Label("Browser", systemImage: "globe") }.tag(2)
            sites.tabItem { Label("Sites", systemImage: "square.grid.2x2") }.tag(3)
        }
        .frame(width: 460, height: 400)
        .sheet(isPresented: Binding(
            get: { editorTarget != nil },
            set: { if !$0 { editorTarget = nil } }
        )) {
            if let target = editorTarget {
                SiteEditorView(target: target, siteStore: siteStore) { editorTarget = nil }
            }
        }
    }

    private var general: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)
            Toggle("Auto Hide when switching apps", isOn: $settings.autoHide)
            Toggle("Keep Above Other Windows", isOn: $settings.alwaysOnTop)
                .onChange(of: settings.alwaysOnTop) { _, _ in onAlwaysOnTopChange() }

            Picker("Side", selection: $settings.panelSide) {
                ForEach(PanelSide.allCases) { side in
                    Text(side.displayName).tag(side)
                }
            }
            .onChange(of: settings.panelSide) { _, newValue in onSideChange(newValue) }

            HStack {
                Text("Width")
                Slider(
                    value: Binding(
                        get: { Double(settings.panelWidth) },
                        set: { onWidthChange(CGFloat($0)) }
                    ),
                    in: Double(PanelGeometry.minWidth)...900
                )
                Text("\(Int(settings.panelWidth)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 56, alignment: .trailing)
            }

            LabeledContent("Height") {
                HStack(spacing: 8) {
                    Text("\(Int((settings.panelHeightRatio * 100).rounded()))% of screen")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText)
                    Button("Reset", action: onResetSize)
                        .disabled(settings.panelHeightRatio >= 1 && settings.panelTopInsetRatio <= 0)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var keyboard: some View {
        Form {
            LabeledContent("Toggle SlideBrowser") {
                HotKeyRecorderView(combo: settings.toggleHotKey) { combo in
                    settings.toggleHotKey = combo
                    onHotKeyChange(combo)
                }
            }

            Section("In-panel shortcuts") {
                shortcutRow("Hide panel", "esc")
                shortcutRow("Address bar", "⌘L")
                shortcutRow("Reload", "⌘R")
                shortcutRow("Back / Forward", "⌘[ / ⌘]")
                shortcutRow("Switch to site 1–9", "⌘1 – ⌘9")
                shortcutRow("Close popup", "⌘W")
                shortcutRow("Settings", "⌘,")
            }
        }
        .formStyle(.grouped)
    }

    private var browser: some View {
        Form {
            Picker("Search Engine", selection: $settings.searchEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }

            Stepper(
                "Keep \(settings.keepAliveLimit) pages alive",
                value: $settings.keepAliveLimit,
                in: 1...8
            )

            Text("Sites marked “Keep page alive” stay loaded regardless of this limit. Cookies and logins always persist.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .formStyle(.grouped)
    }

    private var sites: some View {
        VStack(spacing: 0) {
            List {
                ForEach(siteStore.orderedSites) { site in
                    HStack(spacing: 10) {
                        SiteIconView(site: site, size: 18, favicons: favicons)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.name).font(.system(size: 12, weight: .medium))
                            Text(site.host)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        if let combo = site.hotKey {
                            Text(combo.displayString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        if site.keepAlive {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .help("Keep alive")
                        }
                        Button {
                            siteStore.togglePinned(id: site.id)
                        } label: {
                            Image(systemName: site.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help(site.isPinned ? "Unpin from sidebar" : "Pin to sidebar")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editorTarget = .existing(site) }
                }
                .onMove { source, destination in
                    siteStore.move(fromOffsets: source, toOffset: destination)
                }
            }

            HStack {
                Button("+ Add Site") { editorTarget = .new }
                Spacer()
                Text("Drag to reorder · double-click to edit")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(10)
        }
    }

    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

/// Records a global hotkey by capturing the next key-down while focused.
struct HotKeyRecorderView: NSViewRepresentable {
    let combo: HotKeyCombo?
    let onChange: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.onChange = onChange
        button.combo = combo
        return button
    }

    func updateNSView(_ nsView: HotKeyRecorderButton, context: Context) {
        nsView.onChange = onChange
        if !nsView.isRecording { nsView.combo = combo }
    }
}

final class HotKeyRecorderButton: NSButton {
    var onChange: ((HotKeyCombo) -> Void)?
    private(set) var isRecording = false

    var combo: HotKeyCombo? {
        didSet { title = combo?.displayString ?? "Record Shortcut" }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
        bezelStyle = .rounded
        title = "Record Shortcut"
        target = self
        action = #selector(startRecording)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        title = "Press keys…"
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            title = combo?.displayString ?? "Record Shortcut"
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }
        isRecording = false
        let newCombo = HotKeyCombo(keyCode: event.keyCode, modifierFlags: modifiers.rawValue)
        combo = newCombo
        onChange?(newCombo)
        window?.makeFirstResponder(nil)
    }
}
