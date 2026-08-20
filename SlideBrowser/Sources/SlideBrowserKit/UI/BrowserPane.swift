import SwiftUI

struct BrowserPane: View {
    @ObservedObject var session: WebSession
    @ObservedObject var sessionManager: WebSessionManager
    @ObservedObject var settings: SettingsStore

    @State private var isHoveringChrome = false
    @State private var hoverExitTask: Task<Void, Never>?

    private var showsAddressBar: Bool {
        sessionManager.isAddressBarVisible || isHoveringChrome
    }

    var body: some View {
        ZStack(alignment: .top) {
            content

            // Always mounted: unmounting it on reveal makes hover drop out and oscillate.
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
                .onHover(perform: setChromeHover)

            if session.isLoading, session.estimatedProgress < 1 {
                ProgressView(value: session.estimatedProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }

            if let notice = session.authNotice, session.loadFailure == nil {
                authBanner(notice)
                    .padding(.top, showsAddressBar ? 46 : 8)
                    .padding(.horizontal, 8)
            }

            if showsAddressBar, session.webView != nil {
                AddressBar(
                    session: session,
                    settings: settings,
                    autoFocus: sessionManager.isAddressBarVisible
                ) {
                    sessionManager.isAddressBarVisible = false
                    hoverExitTask?.cancel()
                    isHoveringChrome = false
                }
                .onHover(perform: setChromeHover)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Palette.panelBackground)
        .animation(.easeOut(duration: 0.12), value: showsAddressBar)
    }

    /// Hiding is deferred so the pointer can travel from the trigger strip onto the bar's
    /// controls without the bar disappearing underneath it.
    private func setChromeHover(_ hovering: Bool) {
        hoverExitTask?.cancel()
        guard !hovering else {
            isHoveringChrome = true
            return
        }
        hoverExitTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            isHoveringChrome = false
        }
    }

    private func authBanner(_ notice: EmbeddedAuthNotice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(notice.provider) sign-in may block embedded browsers.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                Button("Open in Default Browser") {
                    NSWorkspace.shared.open(notice.url)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
            }

            Spacer(minLength: 0)

            Button {
                session.authNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        )
    }

    @ViewBuilder
    private var content: some View {
        if let failure = session.loadFailure {
            errorView(failure)
        } else if let webView = session.webView {
            WebViewContainer(webView: webView)
                .id(session.id)
        } else {
            Color.clear.onAppear { session.activate() }
        }
    }

    private func errorView(_ failure: WebLoadFailure) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.secondaryText)
            Text("Unable to Load Page")
                .font(.system(size: 16, weight: .semibold))
            Text(failure.url?.host ?? session.site.name)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
            Text(failure.message)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(failure.code)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.secondaryText.opacity(0.7))

            HStack(spacing: 10) {
                Button("Retry") { session.reload() }
                    .buttonStyle(.borderedProminent)
                Button("Open in Browser") {
                    if let url = failure.url ?? session.site.url { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panelBackground)
    }
}

struct PopupPane: View {
    @ObservedObject var popup: PopupSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Close popup (⌘W)")

                Text(popup.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let url = popup.currentURL {
                    Text(url.host ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.hairline).frame(height: 0.5)
            }

            WebViewContainer(webView: popup.webView)
        }
        .background(Palette.panelBackground)
    }
}
