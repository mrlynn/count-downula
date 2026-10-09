import UserNotifications

/// The buttons under a long-pressed alert. Each category in `NotificationPlan.Category` gets the
/// actions that make sense for that moment; every action opens the app, since each one needs it
/// (a share sheet, the coffin, or ActivityKit, which only starts Live Activities in the foreground).
enum NotificationActions {
    enum Action: String {
        case lockScreen = "lockscreen"
        case share
        case recap
        case coffin
    }

    static func register() {
        let lockScreen = UNNotificationAction(identifier: Action.lockScreen.rawValue, title: "Put on Lock Screen",
                                              options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "lock.iphone"))
        let share = UNNotificationAction(identifier: Action.share.rawValue, title: "Share",
                                         options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "square.and.arrow.up"))
        let recap = UNNotificationAction(identifier: Action.recap.rawValue, title: "Share the Recap",
                                         options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "square.and.arrow.up"))
        let coffin = UNNotificationAction(identifier: Action.coffin.rawValue, title: "Open the Coffin",
                                          options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "sparkles"))
        let actions: [NotificationPlan.Category: [UNNotificationAction]] = [
            .soon: [lockScreen, share],
            .milestone: [share],
            .done: [recap],
            .doneCoffin: [coffin, recap],
            .anniversary: [recap],
        ]
        UNUserNotificationCenter.current().setNotificationCategories(Set(NotificationPlan.Category.allCases.map { category in
            UNNotificationCategory(identifier: category.rawValue, actions: actions[category] ?? [], intentIdentifiers: [])
        }))
    }
}

/// Something a notification action asked the countdown's screen to do once it's open.
enum PendingAction: Equatable {
    case share(UUID)
    case openCoffin(UUID)
}
