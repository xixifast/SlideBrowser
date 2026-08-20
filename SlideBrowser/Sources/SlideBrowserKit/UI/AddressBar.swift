import SwiftUI

/// Hidden browser chrome: revealed on hover near the top edge or via ⌘L.
struct AddressBar: View {
    @ObservedObject var session: WebSession
    @ObservedObject var settings: SettingsStore

    let autoFocus: Bool
    let onDismiss: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            controlButton("chevron.left", enabled: session.canGoBack) { session.goBack() }
            controlButton("chevron.right", enabled: session.canGoForward) { session.goForward() }
            controlButton(session.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                if session.isLoading { session.stopLoading() } else { session.reload() }
            }

            TextField("Search or enter URL", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit(submit)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.fieldBackground)
                )

            controlButton("safari", enabled: session.currentURL != nil) {
                if let url = session.currentURL { NSWorkspace.shared.open(url) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
        .onAppear {
            text = session.currentURL?.absoluteString ?? ""
            if autoFocus { isFocused = true }
        }
        .onExitCommand(perform: onDismiss)
    }

    private func controlButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Palette.primaryText : Palette.secondaryText.opacity(0.5))
    }

    private func submit() {
        guard let classified = URLClassifier.classify(text) else { return }
        switch classified {
        case .navigate(let url):
            session.load(url)
        case .search(let query):
            if let url = settings.searchEngine.searchURL(for: query) { session.load(url) }
        }
        onDismiss()
    }
}
