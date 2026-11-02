import SwiftUI
import EventKit
import CoreLocation

struct LessonScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    let beach: SurfBeach
    let advice: SurfAdvice?
    let forecast: BeachForecast?
    let onSaved: () -> Void
    @State private var start: Date
    @State private var end: Date
    @State private var instructor = ""
    @State private var notes = ""
    @State private var includeGear = true
    @State private var alarmMinutes = 60
    @State private var isSaving = false
    @State private var error: String?
    @State private var calendarName: String?
    @State private var store = EKEventStore()

    init(beach: SurfBeach, day: Date, advice: SurfAdvice?, forecast: BeachForecast?, onSaved: @escaping () -> Void) {
        self.beach = beach
        self.advice = advice
        self.forecast = forecast
        self.onSaved = onSaved
        let proposed = advice?.window?.start
            ?? ForecastClock.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
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
                    Text("All times use the beach timezone: Europe/Lisbon.").font(.caption).foregroundStyle(SurflyTheme.mutedText)
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
                    Picker("Reminder", selection: $alarmMinutes) {
                        Text("At start").tag(0)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("1 day before").tag(1440)
                    }.font(.subheadline)
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").foregroundStyle(SurflyTheme.forecastTeal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Calendar").font(.subheadline.weight(.semibold))
                            Text(calendarName ?? "Your default calendar · permission requested on save")
                                .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SurflyTheme.warmSand, in: RoundedRectangle(cornerRadius: 14))
                    if let error { Text(error).font(.caption).foregroundStyle(SurflyTheme.accentCoralText) }
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(.white) } else { Text("Save to Calendar") }
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
        }
        .environment(\.timeZone, ForecastClock.timeZone)
        .tint(SurflyTheme.forecastTeal)
        .presentationDragIndicator(.visible)
    }

    @MainActor private func save() async {
        guard !isSaving else { return }
        guard start > Date(), end > start else { error = "Choose a future start and a later end time."; return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else {
                error = "Calendar access was not granted. Enable it in Settings to save your lesson."
                return
            }
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
                error = "No writable default calendar is available. Add a calendar in the Calendar app."
                return
            }
            calendarName = calendar.title
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = "Surf lesson · \(beach.name)"
            event.startDate = start
            event.endDate = end
            event.timeZone = ForecastClock.timeZone
            let place = EKStructuredLocation(title: "\(beach.name), \(beach.region)")
            place.geoLocation = beach.location
            event.structuredLocation = place
            var lines = [notes.trimmingCharacters(in: .whitespacesAndNewlines)]
            if !instructor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append("Instructor / school: \(instructor)") }
            // Never attach the Home's recommendation to an unrelated time chosen in the form.
            let relevant = forecast?.hours.filter { $0.time >= start && $0.time <= end } ?? []
            if let forecast, let first = relevant.first, let last = relevant.last,
               first.time.timeIntervalSince(start) < 3600, end.timeIntervalSince(last.time) < 3600,
               Date().timeIntervalSince(forecast.fetchedAt) < 900 {
                lines.append("Open-Meteo forecast retrieved \(ForecastClock.text(forecast.fetchedAt, format: "d MMM yyyy HH:mm")) Europe/Lisbon.")
                for hour in relevant {
                    let wave = hour.waveHeight.map { String(format: "%.1f m", $0) } ?? "unavailable"
                    let wind = hour.windSpeed.map { String(format: "%.0f km/h", $0) } ?? "unavailable"
                    let water = hour.waterTemperature.map { String(format: "%.1f°C", $0) } ?? "unavailable"
                    lines.append("\(ForecastClock.text(hour.time, format: "HH:mm")): waves \(wave), wind \(wind), water \(water).")
                }
                if includeGear { lines.append("Forecast-based gear suggestions: " + ForecastEngine.gear(for: relevant).map(\.label).joined(separator: ", ")) }
            } else {
                lines.append("Forecast and gear checklist unavailable for the selected lesson time. Check again before the lesson.")
            }
            lines.append("Model data, not beach observations. Confirm local conditions and equipment with your instructor. https://open-meteo.com/")
            event.notes = lines.filter { !$0.isEmpty }.joined(separator: "\n\n")
            event.addAlarm(EKAlarm(relativeOffset: -Double(alarmMinutes * 60)))
            try store.save(event, span: .thisEvent)
            dismiss()
            onSaved()
        } catch {
            self.error = "The lesson could not be saved. \(error.localizedDescription)"
        }
    }
}
