import AppIntents
import Foundation

// MARK: - Confirm from the large and extra large widget (standard §1.27 Widgets)
//
// "Confirm" on a To confirm row logs the suggestion as hours, the same write as "Log it" on the
// end-of-visit notification (`NotificationActionRouter`, which checks the profile, the iCloud
// first pull and "might already be logged" at tap time). The app opens to run it: the widget
// extension has no access to the records, and an item that needs a choice (a rental, a kind of
// work) opens its confirm sheet instead. The widget redraws from the new snapshot afterwards.
//
// The type is compiled into the app and the extension; only the app has the body.

struct WidgetConfirmIntent: AppIntent {
    static var title: LocalizedStringResource = "Confirm"
    static var description = IntentDescription("Counts one waiting item toward your hours.")
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Item")
    var key: String

    init() { key = "" }

    init(key: String) { self.key = key }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await WidgetConfirmAction.confirm(key: key)
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
@MainActor
enum WidgetConfirmAction {
    /// Logs the suggestion with `key` for the active profile, then redraws the widget.
    static func confirm(key: String, host: AppModelHost = .shared) async {
        guard !key.isEmpty, let profileId = UserScope.userId else { return }
        let request = NotificationActionRequest(
            actionIdentifier: CaptureNotificationAction.logIt,
            categoryIdentifier: CaptureNotificationAction.categoryIdentifier,
            userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: key)
        )
        await NotificationActionRouter(host: host).handle(request, completion: {})
        host.viewModel.refreshWidgetSurface()
    }
}
#endif
