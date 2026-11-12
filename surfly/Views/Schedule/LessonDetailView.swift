import SwiftUI
import SwiftData
import EventKit
import EventKitUI
import MapKit

struct LessonDetailView: View {
    @Bindable var lesson: SurfLesson
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var calendar: LessonCalendarService
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showCompletion = false
    @State private var showCancel = false
    @State private var showLocalEditor = false
    @State private var busy = false
    @State private var error: String?
    @State private var editor: CalendarEditSession?

    var body: some View {
        ScrollView {
            if auth.userID == lesson.ownerID {
                VStack(alignment: .leading, spacing: 20) {
                    LessonSummaryCard(lesson: lesson)
                    if lesson.isCompleted {
                        SurflyCard(color: SurflyTheme.softMint) {
                            Label("Session logged", systemImage: "checkmark.circle").font(.headline)
                            if let minutes = lesson.waterMinutes, let actualStart = lesson.actualStart {
                                Text("\(minutes) minutes in the water · \(actualStart.formatted(date: .abbreviated, time: .shortened))")
                            }
                            Button("Edit session log") { showCompletion = true }
                            Button("Undo completion") {
                                lesson.status = "planned"
                                lesson.completedAt = nil
                                lesson.actualStart = nil
                                lesson.waterMinutes = nil
                                persist()
                            }
                        }
                    }
                    SurflyCard {
                        Label("Gear Checklist", systemImage: "sparkles").font(.headline)
                        if let fetched = lesson.forecastFetchedAt {
                            Text("Based on forecast retrieved \(fetched.formatted(date: .abbreviated, time: .shortened)). Refresh before your lesson.")
                                .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        }
                        if lesson.gear.isEmpty { Text("No forecast-based checklist for this lesson yet.").font(.subheadline).foregroundStyle(SurflyTheme.mutedText) }
                        ForEach(lesson.gear) { item in
                            Button {
                                if lesson.checkedGearIDs.contains(item.id) { lesson.checkedGearIDs.removeAll { $0 == item.id } }
                                else { lesson.checkedGearIDs.append(item.id) }
                                persist()
                            } label: {
                                HStack {
                                    Text(item.label).foregroundStyle(SurflyTheme.darkSlate)
                                    Spacer()
                                    Image(systemName: lesson.checkedGearIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                                }.padding(.vertical, 8)
                            }.accessibilityLabel("\(item.label), \(lesson.checkedGearIDs.contains(item.id) ? "packed" : "not packed")")
                            Divider()
                        }
                        if lesson.status == "planned", lesson.end > Date() {
                            Button("Refresh forecast & checklist") { Task { await refreshForecast() } }.disabled(busy)
                        }
                    }
                    if let summary = lesson.forecastSummary {
                        DisclosureGroup("Saved forecast") { Text(summary).font(.caption).textSelection(.enabled) }
                    }
                    if !lesson.notes.isEmpty { SurflyCard { Text("Notes").font(.headline); Text(lesson.notes) } }
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: lesson.beach.coordinate))
                        item.name = lesson.beachName
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: { Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    SurflyCard(color: SurflyTheme.warmSand) {
                        Label("Apple Calendar", systemImage: "calendar").font(.headline)
                        Text(lesson.calendarSyncMessage ?? (lesson.calendarExported ? "This lesson is linked to Calendar." : "This lesson is saved on this device."))
                            .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        if lesson.status == "planned" {
                            Button(lesson.calendarExported ? "Update linked calendar event" : "Add to Calendar") {
                                Task {
                                    guard let owner = auth.userID, owner == lesson.ownerID else { return }
                                    busy = true
                                    defer { busy = false }
                                    do {
                                        try await calendar.export(lesson, ownerID: owner)
                                        persist()
                                    } catch { self.error = error.localizedDescription }
                                }
                            }.disabled(busy)
                            if lesson.calendarExported {
                                Button("Edit date and details in Calendar") {
                                    Task {
                                        guard let owner = auth.userID, owner == lesson.ownerID else { return }
                                        busy = true
                                        defer { busy = false }
                                        if !calendar.hasFullAccess, !(await calendar.connect()) { error = calendar.error; return }
                                        guard auth.userID == owner else { return }
                                        do { editor = CalendarEditSession(event: try calendar.eventToEdit(lesson, ownerID: owner)) }
                                        catch { self.error = error.localizedDescription }
                                    }
                                }.disabled(busy)
                            }
                        }
                    }
                    if lesson.status == "planned" {
                        if !lesson.calendarExported {
                            Button("Edit lesson") { showLocalEditor = true }.disabled(busy)
                        }
                        if lesson.start < Date() {
                            Button { showCompletion = true } label: { Label("Log completed session", systemImage: "checkmark.circle") }
                                .buttonStyle(ForecastPrimaryButton())
                        }
                        Button("Cancel lesson", role: .destructive) { showCancel = true }.disabled(busy)
                    }
                    if lesson.status == "cancelled" { Text("This lesson is cancelled.").foregroundStyle(SurflyTheme.accentCoralText) }
                    if busy { ProgressView() }
                    if let error { Text(error).font(.caption).foregroundStyle(SurflyTheme.accentCoralText) }
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
        }
        .background(SurflyTheme.background).foregroundStyle(SurflyTheme.darkSlate).navigationTitle(lesson.beachName)
        .navigationBarTitleDisplayMode(.inline).tint(SurflyTheme.forecastTeal)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showCompletion) { SessionCompletionView(lesson: lesson) }
        .sheet(isPresented: $showLocalEditor) { LocalLessonEditor(lesson: lesson) }
        .sheet(item: $editor) { session in
            CalendarEventEditor(event: session.event, store: calendar.store) { action in
                editor = nil
                guard let owner = auth.userID, owner == lesson.ownerID else { return }
                if action == .deleted { lesson.status = "cancelled" }
                else { calendar.reconcile([lesson], ownerID: owner) }
                persist()
            }
        }
        .alert("Cancel this lesson?", isPresented: $showCancel) {
            Button("Keep lesson", role: .cancel) { }
            Button("Cancel lesson", role: .destructive) {
                guard let owner = auth.userID, owner == lesson.ownerID else { return }
                do { try calendar.cancel(lesson, ownerID: owner); persist() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("A linked Calendar event will be removed. Cancelled lessons do not count towards your progress.") }
        .onChange(of: auth.userID) { _, owner in if owner != lesson.ownerID { dismiss() } }
    }

    private func persist() {
        do { try context.save(); error = nil }
        catch { context.rollback(); self.error = "Could not save the change on this device." }
    }
    private func refreshForecast() async {
        guard let owner = auth.userID, owner == lesson.ownerID else { return }
        let beachID = lesson.beachID
        let start = lesson.start
        let end = lesson.end
        busy = true
        defer { busy = false }
        do {
            let forecast = try await OpenMeteoService().forecast(for: lesson.beach, refresh: true)
            guard auth.userID == owner, lesson.start == start, lesson.end == end, lesson.beachID == beachID else { return }
            guard let snapshot = LessonForecastSnapshot(forecast: forecast, start: start, end: end) else {
                error = "This lesson is outside the available forecast window. Try again closer to the date."
                return
            }
            lesson.gearIDs = snapshot.gear.map(\.rawValue)
            lesson.checkedGearIDs = lesson.checkedGearIDs.filter { lesson.gearIDs.contains($0) }
            lesson.forecastSummary = snapshot.summary
            lesson.forecastFetchedAt = forecast.fetchedAt
            lesson.timeZoneIdentifier = forecast.timeZoneIdentifier
            persist()
        } catch { self.error = error.localizedDescription }
    }
}

struct SessionCompletionView: View {
    @Bindable var lesson: SurfLesson
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var actualStart: Date
    @State private var minutes: String
    @State private var error: String?

    init(lesson: SurfLesson) {
        self.lesson = lesson
        _actualStart = State(initialValue: lesson.actualStart ?? lesson.start)
        _minutes = State(initialValue: lesson.waterMinutes.map(String.init) ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your completed session") {
                    Text(lesson.beachName).font(.headline)
                    DatePicker("Actual start", selection: $actualStart, in: ...Date())
                    TextField("Actual minutes in the water", text: $minutes).keyboardType(.numberPad)
                    Text("Record the time you actually spent in the water. Planned duration is never counted automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Times in \(lesson.timeZoneIdentifier)").font(.caption)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save completed session") {
                    guard auth.userID == lesson.ownerID, lesson.status != "cancelled", let value = Int(minutes),
                          LessonValidation.validCompletion(start: actualStart, minutes: value) else {
                        error = "Enter a completed session with 1–1440 actual minutes, ending in the past."
                        return
                    }
                    lesson.actualStart = actualStart
                    lesson.waterMinutes = value
                    lesson.completedAt = Date()
                    lesson.status = "completed"
                    do { try context.save(); dismiss() }
                    catch { context.rollback(); self.error = "Could not save the session." }
                }
            }.navigationTitle("Log your session")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.environment(\.timeZone, lesson.beach.timeZone).tint(SurflyTheme.forecastTeal)
    }
}

private struct LocalLessonEditor: View {
    @Bindable var lesson: SurfLesson
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var instructor: String
    @State private var notes: String
    @State private var error: String?

    init(lesson: SurfLesson) {
        self.lesson = lesson
        _start = State(initialValue: lesson.start)
        _end = State(initialValue: lesson.end)
        _instructor = State(initialValue: lesson.instructor)
        _notes = State(initialValue: lesson.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson details") {
                    Text(lesson.beachName).font(.headline)
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end, in: start...)
                    Text("Times in \(lesson.timeZoneIdentifier)").font(.caption).foregroundStyle(.secondary)
                    TextField("Instructor or school", text: $instructor)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Text("Changing the time clears the previous forecast and checklist. Refresh them from the lesson page.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save changes") {
                    guard auth.userID == lesson.ownerID, lesson.status == "planned", !lesson.calendarExported, end > start else {
                        error = "This lesson cannot be changed. Check the dates and account."
                        return
                    }
                    if start != lesson.start || end != lesson.end {
                        lesson.gearIDs = []
                        lesson.checkedGearIDs = []
                        lesson.forecastSummary = nil
                        lesson.forecastFetchedAt = nil
                    }
                    lesson.start = start
                    lesson.end = end
                    lesson.instructor = instructor
                    lesson.notes = notes
                    do { try context.save(); dismiss() }
                    catch { context.rollback(); self.error = "Could not save the changes." }
                }.disabled(end <= start)
            }
            .navigationTitle("Edit lesson")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.environment(\.timeZone, lesson.beach.timeZone).tint(SurflyTheme.forecastTeal)
    }
}

private struct CalendarEditSession: Identifiable {
    let id = UUID()
    let event: EKEvent
}

private struct CalendarEventEditor: UIViewControllerRepresentable {
    let event: EKEvent
    let store: EKEventStore
    let completion: (EKEventEditViewAction) -> Void
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let completion: (EKEventEditViewAction) -> Void
        init(completion: @escaping (EKEventEditViewAction) -> Void) { self.completion = completion }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { completion(action) }
    }
}
