import Foundation

enum DurationFormatter {
    static func formattedDuration(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0m" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: seconds) ?? "0m"
    }
}
