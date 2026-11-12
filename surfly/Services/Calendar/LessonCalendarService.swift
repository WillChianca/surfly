import Foundation
import EventKit
import Combine
import CoreLocation

enum LessonCalendarError: LocalizedError {
    case denied, noCalendar, fullAccessNeeded, missingEvent
    var errorDescription: String? {
        switch self {
        case .denied: "Calendar permission was not granted. Your lesson remains saved in My Schedule."
        case .noCalendar: "No writable default calendar is available. Set one in Apple Calendar."
        case .fullAccessNeeded: "Connect Calendar with full access to update an existing event without duplicating it."
        case .missingEvent: "The linked event could not be found. It may have been deleted or moved to an unavailable calendar."
        }
    }
}

@MainActor
final class LessonCalendarService: ObservableObject {
    let store = EKEventStore()
    @Published private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    @Published var error: String?
    var hasFullAccess: Bool { authorization == .fullAccess }

    func refreshAuthorization() { authorization = EKEventStore.authorizationStatus(for: .event) }

    func connect() async -> Bool {
        do {
            let allowed = try await store.requestFullAccessToEvents()
            refreshAuthorization()
            error = allowed ? nil : "Enable full calendar access in Settings to read and synchronise your surf lessons."
            return allowed
        } catch { self.error = error.localizedDescription; return false }
    }

    func export(_ lesson: SurfLesson, ownerID: String) async throws {
        guard lesson.ownerID == ownerID else { throw LessonCalendarError.denied }
        refreshAuthorization()
        if authorization != .fullAccess && authorization != .writeOnly {
            guard try await store.requestWriteOnlyAccessToEvents() else { throw LessonCalendarError.denied }
            refreshAuthorization()
        }
        let event: EKEvent
        if lesson.calendarExported {
            guard hasFullAccess else { throw LessonCalendarError.fullAccessNeeded }
            guard let existing = linkedEvent(for: lesson) else { throw LessonCalendarError.missingEvent }
            event = existing
        } else {
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { throw LessonCalendarError.noCalendar }
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }
        guard event.calendar.allowsContentModifications else { throw LessonCalendarError.noCalendar }
        event.title = "Surf lesson · \(lesson.beachName)"
        event.startDate = lesson.start
        event.endDate = lesson.end
        event.timeZone = lesson.beach.timeZone
        event.url = lesson.eventURL
        let place = EKStructuredLocation(title: "\(lesson.beachName), \(lesson.region)")
        place.geoLocation = lesson.beach.location
        event.structuredLocation = place
        event.notes = [lesson.notes, lesson.instructor.isEmpty ? nil : "Instructor: \(lesson.instructor)", lesson.forecastSummary,
                       lesson.gear.isEmpty ? nil : "Gear suggestions: " + lesson.gear.map(\.label).joined(separator: ", ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        event.alarms = lesson.reminderMinutes < 0 ? [] : [EKAlarm(relativeOffset: -Double(lesson.reminderMinutes * 60))]
        try store.save(event, span: .thisEvent)
        lesson.calendarEventID = event.eventIdentifier
        lesson.calendarExported = true
        lesson.calendarSyncMessage = nil
    }

    private func linkedEvent(for lesson: SurfLesson) -> EKEvent? {
        if let id = lesson.calendarEventID, let event = store.event(withIdentifier: id) { return event }
        // EventKit identifiers may change on sync. Our stable URL recovers app-created events.
        let start = lesson.start.addingTimeInterval(-365 * 86400)
        let end = lesson.end.addingTimeInterval(365 * 86400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).first { $0.url == lesson.eventURL }
    }

    func eventToEdit(_ lesson: SurfLesson, ownerID: String) throws -> EKEvent {
        refreshAuthorization()
        guard ownerID == lesson.ownerID, hasFullAccess else { throw LessonCalendarError.fullAccessNeeded }
        guard let event = linkedEvent(for: lesson) else { throw LessonCalendarError.missingEvent }
        return event
    }

    func reconcile(_ lessons: [SurfLesson], ownerID: String) {
        refreshAuthorization()
        guard hasFullAccess else { return }
        for lesson in lessons where lesson.ownerID == ownerID && lesson.calendarExported && lesson.status == "planned" {
            guard let event = linkedEvent(for: lesson) else {
                lesson.calendarSyncMessage = "Linked event not found. The local lesson is retained; check Apple Calendar."
                continue
            }
            if event.status == .canceled { lesson.status = "cancelled" }
            if lesson.start != event.startDate || lesson.end != event.endDate {
                lesson.start = event.startDate
                lesson.end = event.endDate
                lesson.gearIDs = []
                lesson.checkedGearIDs = []
                lesson.forecastSummary = nil
                lesson.forecastFetchedAt = nil
            }
            if let point = event.structuredLocation?.geoLocation,
               point.distance(from: lesson.beach.location) > 100 {
                lesson.latitude = point.coordinate.latitude
                lesson.longitude = point.coordinate.longitude
                lesson.beachID = BeachDiscoveryService.identifier(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
                lesson.beachName = event.structuredLocation?.title ?? "Calendar location"
                lesson.region = ""
                lesson.seawardBearing = nil
                lesson.gearIDs = []
                lesson.checkedGearIDs = []
                lesson.forecastSummary = nil
                lesson.forecastFetchedAt = nil
            }
            if let zone = event.timeZone { lesson.timeZoneIdentifier = zone.identifier }
            lesson.calendarEventID = event.eventIdentifier
            lesson.calendarSyncMessage = nil
        }
    }

    func cancel(_ lesson: SurfLesson, ownerID: String) throws {
        guard lesson.ownerID == ownerID else { throw LessonCalendarError.denied }
        if lesson.calendarExported {
            refreshAuthorization()
            guard hasFullAccess else { throw LessonCalendarError.fullAccessNeeded }
            guard let event = linkedEvent(for: lesson) else { throw LessonCalendarError.missingEvent }
            try store.remove(event, span: .thisEvent)
        }
        lesson.status = "cancelled"
        lesson.calendarSyncMessage = nil
    }

    func importCandidates(from: Date, to: Date, existing: [SurfLesson]) -> [EKEvent] {
        guard hasFullAccess else { return [] }
        let ids = Set(existing.compactMap(\.calendarEventID))
        let urls = Set(existing.map(\.eventURL))
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil)).filter {
            ($0.title ?? "").localizedCaseInsensitiveContains("surf") && $0.structuredLocation?.geoLocation != nil
                && $0.status != .canceled && !ids.contains($0.eventIdentifier ?? "")
                && !($0.url.map { urls.contains($0) } ?? false)
        }.sorted { $0.startDate < $1.startDate }
    }
}
