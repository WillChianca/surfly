import SwiftUI
import EventKit
import CoreLocation
import SwiftData

struct LessonScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var calendar: LessonCalendarService
    let beach: SurfBeach
    let advice: SurfAdvice?
    @State private var forecast: BeachForecast?
    @State private var forecastError: String?
    let onSaved: () -> Void
    @State private var start: Date
    @State private var end: Date
    @State private var instructor = ""
    @State private var notes = ""
    @State private var includeGear = true
    @State private var alarmMinutes = AppSettings.defaultReminder
    @State private var syncCalendar = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var savedLesson: SurfLesson?
    private var timeZone: TimeZone { forecast?.timeZone ?? beach.timeZone }

    init(beach: SurfBeach, day: Date, advice: SurfAdvice?, forecast: BeachForecast?, onSaved: @escaping () -> Void) {
        self.beach = beach
        self.advice = advice
        _forecast = State(initialValue: forecast)
        self.onSaved = onSaved
        let proposed = advice?.window?.start
            ?? ForecastClock.calendar(in: forecast?.timeZone ?? beach.timeZone).date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        let start = max(proposed, Date().addingTimeInterval(3600))
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(7200))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Schedule a lesson").font(.title.weight(.bold))
                        Text("Make a little time for the ocean.").font(.subheadline).foregroundStyle(SurflyTheme.mutedText)
                    }
                    VStack(spacing: 0) {
                        DatePicker("Date", selection: $start, in: Date()..., displayedComponents: .date)
                        Divider().padding(.vertical, 10)
                        DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                        Divider().padding(.vertical, 10)
                        DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    Text("Times in \(timeZone.identifier)").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                    VStack(alignment: .leading, spacing: 14) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("BEACH LOCATION").font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                                Text("\(beach.name), \(beach.region)")
                            }
                        } icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(SurflyTheme.forecastTeal) }
                        Divider()
                        TextField("Instructor or school (optional)", text: $instructor)
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading) {
                        Text("Notes").font(.caption.weight(.semibold))
                        TextField("Anything to remember for your lesson?", text: $notes, axis: .vertical).lineLimit(3...5)
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    Toggle(isOn: $includeGear) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Sync Gear Checklist to Calendar Alert").font(.subheadline.weight(.semibold))
                            Text("Attach the matching forecast and gear suggestions to your event notes.")
                                .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        }
                    }
                    if let forecastError { Text(forecastError).font(.caption).foregroundStyle(SurflyTheme.mutedText) }
                    Toggle("Add to Apple Calendar", isOn: $syncCalendar)
                    Text("Your lesson is saved in My Schedule even if Calendar is unavailable.").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                    Picker("Reminder", selection: $alarmMinutes) {
                        Text("None").tag(-1)
                        Text("At start").tag(0)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("1 day before").tag(1440)
                    }.font(.subheadline)
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").foregroundStyle(SurflyTheme.forecastTeal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Calendar").font(.subheadline.weight(.semibold))
                            Text(syncCalendar ? "Your default calendar · permission requested on save" : "Calendar export is off · saved in My Schedule")
                                .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SurflyTheme.warmSand, in: RoundedRectangle(cornerRadius: 14))
                    if let error { Text(error).font(.caption).foregroundStyle(SurflyTheme.accentCoralText) }
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(.white) } else { Text("Save lesson") }
                    }.buttonStyle(ForecastPrimaryButton()).disabled(isSaving || end <= start)
                }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(SurflyTheme.background)
            .foregroundStyle(SurflyTheme.darkSlate)
            .navigationTitle("NEW EVENT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .topBarTrailing) { Image(systemName: "calendar.badge.plus") }
            }
            .onChange(of: start) { old, new in
                end = new.addingTimeInterval(max(3600, end.timeIntervalSince(old)))
            }
            .task(id: beach.id) {
                if let forecast, Date().timeIntervalSince(forecast.fetchedAt) < 900 { return }
                do {
                    let value = try await OpenMeteoService().forecast(for: beach)
                    guard !Task.isCancelled else { return }
                    forecast = value
                } catch {
                    if !Task.isCancelled { forecastError = "Forecast unavailable. The lesson can still be saved and refreshed later." }
                }
            }
        }
        .environment(\.timeZone, timeZone)
        .interactiveDismissDisabled(isSaving)
        .tint(SurflyTheme.forecastTeal)
        .presentationDragIndicator(.visible)
    }

    @MainActor private func save() async {
        guard !isSaving, let owner = auth.userID else { error = "Sign in to save a lesson."; return }
        guard start > Date(), end > start else { error = "Choose a future start and a later end time."; return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        // If persistence of a Calendar link fails, retry the same record, never create a duplicate.
        let lesson: SurfLesson
        if let existing = savedLesson { lesson = existing }
        else {
            var resolved = beach
            resolved.timeZoneIdentifier = timeZone.identifier
            let snapshot = includeGear ? forecast.flatMap { LessonForecastSnapshot(forecast: $0, start: start, end: end) } : nil
            lesson = SurfLesson(ownerID: owner, beach: resolved, start: start, end: end, instructor: instructor,
                                notes: notes, reminderMinutes: alarmMinutes, gear: snapshot?.gear ?? [],
                                forecastSummary: snapshot?.summary, forecastFetchedAt: snapshot == nil ? nil : forecast?.fetchedAt)
            context.insert(lesson)
            do { try context.save(); savedLesson = lesson }
            catch { context.rollback(); self.error = "Could not save the lesson: \(error.localizedDescription)"; return }
        }
        if syncCalendar, auth.userID == owner, !lesson.calendarExported {
            do { try await calendar.export(lesson, ownerID: owner) }
            catch { lesson.calendarSyncMessage = error.localizedDescription }
        }
        do { try context.save() }
        catch { self.error = "The lesson was saved, but the calendar link could not be stored. Check Apple Calendar before retrying."; return }
        dismiss()
        onSaved()
    }
}

struct LessonForecastSnapshot {
    let gear: [GearItem]
    let summary: String

    init?(forecast: BeachForecast, start: Date, end: Date, now: Date = Date()) {
        guard end > start, now.timeIntervalSince(forecast.fetchedAt) >= 0,
              now.timeIntervalSince(forecast.fetchedAt) < 900 else { return nil }
        let hours = forecast.hours.filter { $0.time < end && $0.time.addingTimeInterval(3600) > start }
        guard let first = hours.first, let last = hours.last, first.time <= start,
              last.time.addingTimeInterval(3600) >= end,
              zip(hours, hours.dropFirst()).allSatisfy({ pair in pair.1.time.timeIntervalSince(pair.0.time) == 3600 }) else { return nil }
        gear = ForecastEngine.gear(for: hours)
        let rows = hours.map { hour in
            let wave = hour.waveHeight.map { String(format: "%.1f m", $0) } ?? "unavailable"
            let wind = hour.windSpeed.map { String(format: "%.0f km/h", $0) } ?? "unavailable"
            let water = hour.waterTemperature.map { String(format: "%.1f°C", $0) } ?? "unavailable"
            return "\(ForecastClock.text(hour.time, format: "d MMM HH:mm", timeZone: forecast.timeZone)): waves \(wave), wind \(wind), water \(water)."
        }
        summary = "Open-Meteo model forecast retrieved \(ForecastClock.text(forecast.fetchedAt, format: "d MMM yyyy HH:mm", timeZone: forecast.timeZone)) \(forecast.timeZoneIdentifier).\n"
            + rows.joined(separator: "\n") + "\nForecast, not a beach observation. Confirm conditions with your instructor. https://open-meteo.com/"
    }
}
