import SwiftUI
import SwiftData
import EventKit

struct MyScheduleView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var selection: BeachSelectionStore
    @EnvironmentObject private var calendar: LessonCalendarService
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SurfLesson.start) private var allLessons: [SurfLesson]
    @State private var selectedDate = Date()
    @State private var showBeachPicker = false
    @State private var draftBeach: SurfBeach?
    @State private var pendingBeach: SurfBeach?
    @State private var showImport = false
    @State private var error: String?
    @State private var connecting = false

    private var lessons: [SurfLesson] { allLessons.filter { $0.ownerID == auth.userID && $0.status != "cancelled" } }
    private var dayLessons: [SurfLesson] { lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: selectedDate) } }
    private var upcoming: [SurfLesson] {
        lessons.filter { candidate in
            candidate.status == "planned" && candidate.end > Date() && !dayLessons.contains { $0.id == candidate.id }
        }
    }
    private var readyToLog: [SurfLesson] { Array(lessons.filter { $0.status == "planned" && $0.end <= Date() }.reversed()) }
    private var week: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SurflyPageHeader(eyebrow: "Plan ahead", title: "My Schedule")
                    HStack {
                        Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        Spacer()
                        Text(selectedDate.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(week, id: \.self) { day in
                                let chosen = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                                Button { selectedDate = day } label: {
                                    VStack(spacing: 5) {
                                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                                        Text(day.formatted(.dateTime.day())).font(.headline)
                                        Circle().fill(lessons.contains { Calendar.current.isDate($0.start, inSameDayAs: day) } ? SurflyTheme.accentCoralText : .clear)
                                            .frame(width: 4, height: 4)
                                    }.frame(width: 48, height: 68).foregroundStyle(chosen ? .white : SurflyTheme.darkSlate)
                                        .background(chosen ? SurflyTheme.forecastTeal : .white, in: RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
                            }
                        }
                    }
                    Text("Calendar days shown in \(TimeZone.current.identifier). Each lesson shows its beach time.")
                        .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                    if dayLessons.isEmpty {
                        SurflyCard {
                            Label("A little space for the ocean", systemImage: "sun.horizon")
                                .font(.headline)
                            Text("No lessons on this day. Choose another date or schedule a lesson.")
                                .font(.subheadline).foregroundStyle(SurflyTheme.mutedText)
                        }
                    } else {
                        ForEach(dayLessons) { lesson in
                            NavigationLink { LessonDetailView(lesson: lesson) } label: { LessonSummaryCard(lesson: lesson) }.buttonStyle(.plain)
                        }
                    }
                    Button { showBeachPicker = true } label: { Label("Schedule another lesson", systemImage: "calendar.badge.plus") }
                        .buttonStyle(ForecastPrimaryButton())
                    if !upcoming.isEmpty {
                        Text("Upcoming lessons").font(.title3.weight(.bold))
                        ForEach(upcoming) { lesson in
                            NavigationLink { LessonDetailView(lesson: lesson) } label: { LessonSummaryCard(lesson: lesson) }.buttonStyle(.plain)
                        }
                    }
                    if !readyToLog.isEmpty {
                        Text("Ready to log").font(.title3.weight(.bold))
                        Text("Confirm which lessons you attended to update your progress.").font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        ForEach(readyToLog) { lesson in
                            NavigationLink { LessonDetailView(lesson: lesson) } label: { LessonSummaryCard(lesson: lesson) }.buttonStyle(.plain)
                        }
                    }
                    SurflyCard(color: SurflyTheme.warmSand) {
                        Label("Apple Calendar", systemImage: "calendar").font(.headline)
                        Text(calendar.hasFullAccess ? "Linked lessons refresh when Calendar changes." : "Connect to read changes and import surf lessons. Your local schedule works without Calendar access.")
                            .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        if calendar.hasFullAccess {
                            Button("Import existing surf lessons") { showImport = true }
                            Button("Refresh linked lessons") { refreshCalendar() }
                        } else {
                            Button(connecting ? "Connecting…" : "Connect Calendar") {
                                Task {
                                    connecting = true
                                    if await calendar.connect() { refreshCalendar() }
                                    connecting = false
                                }
                            }.disabled(connecting)
                        }
                        if let error = error ?? calendar.error { Text(error).font(.caption).foregroundStyle(SurflyTheme.accentCoralText) }
                    }
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(SurflyTheme.background).foregroundStyle(SurflyTheme.darkSlate)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showBeachPicker, onDismiss: { draftBeach = pendingBeach; pendingBeach = nil }) {
                BeachSearchView(onSelect: { pendingBeach = $0 })
            }
            .sheet(item: $draftBeach) { beach in
                LessonScheduleView(beach: beach, day: selectedDate, advice: nil, forecast: nil) { refreshCalendar() }
            }
            .sheet(isPresented: $showImport) { CalendarImportView(existing: allLessons) }
            .onAppear { refreshCalendar() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshCalendar() } }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refreshCalendar() }
            .refreshable { refreshCalendar() }
        }.tint(SurflyTheme.forecastTeal)
    }

    private func moveWeek(_ value: Int) { selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: value, to: selectedDate) ?? selectedDate }
    private func refreshCalendar() {
        guard let owner = auth.userID else { return }
        calendar.reconcile(allLessons, ownerID: owner)
        do { if context.hasChanges { try context.save() }; error = nil }
        catch { context.rollback(); self.error = "Calendar changes could not be saved locally." }
    }
}

struct LessonSummaryCard: View {
    let lesson: SurfLesson
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                Text(ForecastClock.text(lesson.start, format: "d", timeZone: lesson.beach.timeZone)).font(.largeTitle.weight(.bold))
                Text(ForecastClock.text(lesson.start, format: "MMM", timeZone: lesson.beach.timeZone).uppercased()).font(.caption.weight(.bold))
            }.frame(width: 58).padding(.vertical, 8).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 9) {
                Text(lesson.status == "cancelled" ? "CANCELLED" : lesson.isCompleted ? "COMPLETED" : lesson.start <= Date() ? "SESSION TO LOG" : "PLANNED LESSON").font(.caption2.weight(.bold))
                Text(lesson.title).font(.headline)
                Label(lesson.timeLabel, systemImage: "clock").font(.caption)
                Label(lesson.beachName, systemImage: "mappin.and.ellipse").font(.caption)
                Text(lesson.timeZoneIdentifier).font(.caption2).opacity(0.85)
                Text(lesson.calendarSyncMessage != nil ? "Calendar needs attention" : lesson.calendarExported ? "Synced to Calendar" : "Saved on this device")
                    .font(.caption2).opacity(0.85)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
            .background(SurflyTheme.deepTeal, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CalendarImportView: View {
    @EnvironmentObject private var calendar: LessonCalendarService
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let existing: [SurfLesson]
    @State private var events: [EKEvent] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Text("Choose a surf event to add to this account. Only events with a mapped location are shown, from the past year and next year. Imported events remain planned until you confirm attendance.")
                    .font(.caption).foregroundStyle(.secondary)
                if events.isEmpty { Text("No unlinked surf lessons found.") }
                ForEach(events, id: \.calendarItemIdentifier) { event in
                    Button {
                        guard let owner = auth.userID, let point = event.structuredLocation?.geoLocation else { return }
                        let beach = SurfBeach(id: BeachDiscoveryService.identifier(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude),
                                              name: event.structuredLocation?.title ?? "Calendar beach", region: "",
                                              latitude: point.coordinate.latitude, longitude: point.coordinate.longitude,
                                              seawardBearing: nil, timeZoneIdentifier: event.timeZone?.identifier ?? TimeZone.current.identifier,
                                              source: "Imported calendar location")
                        let lesson = SurfLesson(ownerID: owner, beach: beach, start: event.startDate, end: event.endDate,
                                                notes: event.notes ?? "", reminderMinutes: -1)
                        lesson.calendarExported = true
                        lesson.calendarEventID = event.eventIdentifier
                        context.insert(lesson)
                        do { try context.save(); dismiss() }
                        catch { context.rollback(); self.error = "Could not import the lesson." }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title ?? "Surf lesson").font(.headline)
                            Text(event.startDate.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text(event.structuredLocation?.title ?? "").font(.caption)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Import surf lessons")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                events = calendar.importCandidates(from: Date().addingTimeInterval(-365 * 86400), to: Date().addingTimeInterval(365 * 86400), existing: existing)
            }
        }
    }
}
