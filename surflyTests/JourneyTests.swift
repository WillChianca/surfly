import XCTest
import SwiftData
import CoreLocation
@testable import surfly

/// Synthetic test inputs are isolated to XCTest; no sample sessions are installed in the app.
@MainActor
final class JourneyTests: XCTestCase {
    private var beach: SurfBeach { SurfBeach.catalogue[0] }
    private var now: Date { ISO8601DateFormatter().date(from: "2030-01-09T15:00:00Z")! }

    private func lesson(owner: String = "owner-a", daysAgo: Int = 1, minutes: Int? = nil) -> SurfLesson {
        let start = now.addingTimeInterval(-Double(daysAgo) * 86400)
        let item = SurfLesson(ownerID: owner, beach: beach, start: start, end: start.addingTimeInterval(7200))
        if let minutes {
            item.status = "completed"
            item.actualStart = start
            item.waterMinutes = minutes
            item.completedAt = now
        }
        return item
    }

    func testAnalyticsExcludePlannedCancelledAndOtherAccounts() {
        let completed = lesson(minutes: 45)
        let planned = lesson()
        let cancelled = lesson(minutes: 90)
        cancelled.status = "cancelled"
        let other = lesson(owner: "owner-b", minutes: 120)
        let result = ProgressSummary(lessons: [completed, planned, cancelled, other], ownerID: "owner-a", now: now)
        XCTAssertEqual(result.totalClasses, 1)
        XCTAssertEqual(result.waterMinutes, 45)
        XCTAssertEqual(result.mostVisited, beach.name)
        XCTAssertEqual(result.mostVisitedCount, 1)
    }

    func testStreakCrossesYearBoundaryAndStopsAtGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let result = ProgressSummary(lessons: [lesson(daysAgo: 1, minutes: 20), lesson(daysAgo: 8, minutes: 30),
                                             lesson(daysAgo: 15, minutes: 40), lesson(daysAgo: 29, minutes: 50)],
                                     ownerID: "owner-a", now: now, calendar: calendar)
        XCTAssertEqual(result.currentStreak, 3)
        let expired = ProgressSummary(lessons: [lesson(daysAgo: 15, minutes: 40)], ownerID: "owner-a", now: now, calendar: calendar)
        XCTAssertEqual(expired.currentStreak, 0)
    }

    func testCompletionRequiresActualPositiveTimeEndingInPast() {
        XCTAssertFalse(LessonValidation.validCompletion(start: now, minutes: 30, now: now))
        XCTAssertFalse(LessonValidation.validCompletion(start: now.addingTimeInterval(-3600), minutes: 0, now: now))
        XCTAssertFalse(LessonValidation.validCompletion(start: now.addingTimeInterval(-3600), minutes: 120, now: now))
        XCTAssertTrue(LessonValidation.validCompletion(start: now.addingTimeInterval(-3600), minutes: 60, now: now))
    }

    func testSwiftDataPersistsChecklistAndIsolatesAccountQueries() throws {
        let container = try ModelContainer(for: SurfLesson.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let writer = ModelContext(container)
        let item = lesson(minutes: 60)
        item.gearIDs = [GearItem.softboard.rawValue]
        item.checkedGearIDs = item.gearIDs
        writer.insert(item)
        writer.insert(lesson(owner: "owner-b", minutes: 100))
        try writer.save()
        let reader = ModelContext(container)
        let owner = "owner-a"
        let descriptor = FetchDescriptor<SurfLesson>(predicate: #Predicate { $0.ownerID == owner })
        let saved = try reader.fetch(descriptor)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.checkedGearIDs, [GearItem.softboard.rawValue])
        XCTAssertEqual(saved.first?.waterMinutes, 60)
    }

    func testLocationRejectsStaleInvalidAndInaccurateFixes() {
        func fix(age: TimeInterval = 0, accuracy: Double = 20, latitude: Double = 39) -> CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: -9), altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: now.addingTimeInterval(-age))
        }
        XCTAssertTrue(BeachLocationService.isUsable(fix(), now: now))
        XCTAssertFalse(BeachLocationService.isUsable(fix(age: 301), now: now))
        XCTAssertFalse(BeachLocationService.isUsable(fix(accuracy: -1), now: now))
        XCTAssertFalse(BeachLocationService.isUsable(fix(accuracy: 6000), now: now))
        XCTAssertFalse(BeachLocationService.isUsable(fix(latitude: 100), now: now))
    }

    func testManualSelectionWinsOverPendingGPSLookup() async throws {
        let suite = "surfly-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BeachSelectionStore(defaults: defaults)
        store.followsLocation = true
        let manual = SurfBeach.catalogue[4]
        await store.findNearest(to: beach.location) { _ in
            store.select(manual)
            return [self.beach]
        }
        XCTAssertEqual(store.selected?.id, manual.id)
        XCTAssertFalse(store.followsLocation)
    }

    func testNoPortugueseBeachFallbackForLocationAbroad() async throws {
        let suite = "surfly-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BeachSelectionStore(defaults: defaults)
        store.followsLocation = true
        await store.findNearest(to: CLLocation(latitude: -33.89, longitude: 151.27)) { _ in [] }
        XCTAssertNil(store.selected)
        XCTAssertNotNil(store.message)
    }

    func testFavouritesAndRecentBeachesSurviveReloadWithoutDuplication() throws {
        let suite = "surfly-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BeachSelectionStore(defaults: defaults)
        store.select(beach)
        store.select(beach)
        store.toggleFavourite(beach)
        let reloaded = BeachSelectionStore(defaults: defaults)
        XCTAssertEqual(reloaded.recent.count, 1)
        XCTAssertEqual(reloaded.selected?.id, beach.id)
        XCTAssertEqual(reloaded.favourites.map(\.id), [beach.id])
    }

    func testGlobalForecastGroupsHoursByBeachTimezone() {
        let instant = ISO8601DateFormatter().date(from: "2030-06-01T23:30:00Z")!
        let hour = ForecastHour(time: instant, waveHeight: nil, wavePeriod: nil, waveDirection: nil,
                                swellHeight: nil, swellPeriod: nil, swellDirection: nil, waterTemperature: nil,
                                airTemperature: nil, windSpeed: nil, windDirection: nil, windGusts: nil, uvIndex: nil, isDay: true)
        let forecast = BeachForecast(beach: beach, hours: [hour], sunsets: [], fetchedAt: instant,
                                     marineLatitude: beach.latitude, marineLongitude: beach.longitude, timeZoneIdentifier: "Asia/Tokyo")
        XCTAssertEqual(ForecastClock.text(instant, format: "yyyy-MM-dd", timeZone: forecast.timeZone), "2030-06-02")
        XCTAssertEqual(forecast.hours(on: forecast.calendar.startOfDay(for: instant)).count, 1)
    }

    func testMilesAreConvertedAndNotJustRelabelled() {
        XCTAssertEqual(AppSettings.distance(1609.344, unit: "mi"), String(format: "%.1f mi", 1.0))
        XCTAssertEqual(AppSettings.distance(1000, unit: "km"), String(format: "%.1f km", 1.0))
    }
}
