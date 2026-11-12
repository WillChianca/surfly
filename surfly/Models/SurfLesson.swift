import Foundation
import SwiftData

@Model
final class SurfLesson {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var beachID: String
    var beachName: String
    var region: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var seawardBearing: Double?
    var start: Date
    var end: Date
    var instructor: String
    var notes: String
    var reminderMinutes: Int
    var status: String
    var createdAt: Date
    var calendarEventID: String?
    var calendarExported: Bool
    var calendarSyncMessage: String?
    var completedAt: Date?
    var actualStart: Date?
    var waterMinutes: Int?
    var gearIDs: [String]
    var checkedGearIDs: [String]
    var forecastSummary: String?
    var forecastFetchedAt: Date?

    init(ownerID: String, beach: SurfBeach, start: Date, end: Date, instructor: String = "", notes: String = "",
         reminderMinutes: Int = 60, gear: [GearItem] = [], forecastSummary: String? = nil, forecastFetchedAt: Date? = nil) {
        id = UUID()
        self.ownerID = ownerID
        beachID = beach.id
        beachName = beach.name
        region = beach.region
        latitude = beach.latitude
        longitude = beach.longitude
        timeZoneIdentifier = beach.timeZone.identifier
        seawardBearing = beach.seawardBearing
        self.start = start
        self.end = end
        self.instructor = instructor
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        status = "planned"
        createdAt = Date()
        calendarExported = false
        gearIDs = gear.map(\.rawValue)
        checkedGearIDs = []
        self.forecastSummary = forecastSummary
        self.forecastFetchedAt = forecastFetchedAt
    }

    var beach: SurfBeach {
        SurfBeach(id: beachID, name: beachName, region: region, latitude: latitude, longitude: longitude,
                  seawardBearing: seawardBearing, timeZoneIdentifier: timeZoneIdentifier, source: "Saved lesson")
    }
    var gear: [GearItem] { gearIDs.compactMap(GearItem.init(rawValue:)) }
    var eventURL: URL { URL(string: "surfly://lesson/\(id.uuidString)")! }
    var isCompleted: Bool { status == "completed" && actualStart != nil && (waterMinutes ?? 0) > 0 }
    var title: String { instructor.isEmpty ? "Surf lesson" : "Surf lesson · \(instructor)" }
    var timeLabel: String {
        "\(ForecastClock.text(start, format: "HH:mm", timeZone: beach.timeZone)) – \(ForecastClock.text(end, format: "HH:mm", timeZone: beach.timeZone))"
    }
}

enum LessonValidation {
    static func validCompletion(start: Date, minutes: Int, now: Date = Date()) -> Bool {
        minutes > 0 && minutes <= 1440 && start.addingTimeInterval(Double(minutes) * 60) <= now
    }
}

struct ProgressSummary {
    let totalClasses: Int
    let waterMinutes: Int
    let currentStreak: Int
    let mostVisited: String?
    let mostVisitedCount: Int

    init(lessons: [SurfLesson], ownerID: String, now: Date = Date(), calendar: Calendar = .current) {
        let completed = lessons.filter { $0.ownerID == ownerID && $0.isCompleted && ($0.actualStart ?? .distantFuture) <= now }
        totalClasses = completed.count
        waterMinutes = completed.reduce(0) { $0 + ($1.waterMinutes ?? 0) }
        let counts = Dictionary(grouping: completed, by: \.beachID)
            .map { (name: $0.value.first?.beachName ?? "", count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        mostVisited = counts.first?.name
        mostVisitedCount = counts.first?.count ?? 0
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 4
        let weeks = Set(completed.compactMap { lesson in
            lesson.actualStart.flatMap { weekCalendar.dateInterval(of: .weekOfYear, for: $0)?.start }
        })
        var cursor = weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        if !weeks.contains(cursor) { cursor = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        currentStreak = streak
    }
}
