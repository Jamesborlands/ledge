import Foundation

enum Settings {
    static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            "shakeEnabled": false,
            "notchEnabled": true,
            "shakeSensitivity": 1,
            "removeAfterDrag": false,
            "historyLimit": 50,
        ])
    }

    static var shakeEnabled: Bool { defaults.bool(forKey: "shakeEnabled") }
    static var notchEnabled: Bool { defaults.bool(forKey: "notchEnabled") }
    static var removeAfterDrag: Bool { defaults.bool(forKey: "removeAfterDrag") }
    static var historyLimit: Int { max(10, defaults.integer(forKey: "historyLimit")) }

    /// Direction changes needed, and how far (in points) each swing must travel.
    static var shakeThresholds: (reversals: Int, travel: CGFloat) {
        switch defaults.integer(forKey: "shakeSensitivity") {
        case 0: return (4, 40)
        case 2: return (2, 18)
        default: return (3, 28)
        }
    }

    static var didFirstLaunch: Bool {
        get { defaults.bool(forKey: "didFirstLaunch") }
        set { defaults.set(newValue, forKey: "didFirstLaunch") }
    }
}
