import AppKit
import WebKit

/// Native presentation of the dialogs WebKit asks a browser to show. Shared by site sessions and
/// popups; previously each carried its own copy.
@MainActor
enum WebDialogPresenter {
    static func alert(message: String, origin: String, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = origin
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completion()
    }

    static func confirm(
        message: String,
        origin: String,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = origin
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completion(alert.runModal() == .alertFirstButtonReturn)
    }

    static func prompt(
        message: String,
        defaultText: String?,
        origin: String,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = origin
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        completion(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    /// Backs `<input type="file">`. Sandbox access comes from the user's selection alone.
    static func chooseFiles(
        parameters: WKOpenPanelParameters,
        completion: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { response in
            completion(response == .OK ? panel.urls : nil)
        }
    }
}
