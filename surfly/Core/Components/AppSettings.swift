import Foundation

enum AppSettings {
    static func distance(_ metres: Double, unit: String = UserDefaults.standard.string(forKey: "distanceUnit") ?? "km") -> String {
        let divisor = unit == "mi" ? 1609.344 : 1000.0
        return String(format: "%.1f %@", metres / divisor, unit == "mi" ? "mi" : "km")
    }
    static var aiEnabled: Bool { UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? true }
    static var defaultReminder: Int { UserDefaults.standard.object(forKey: "defaultReminder") as? Int ?? 60 }
}
