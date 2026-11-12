import SwiftUI
import SwiftData
import CoreLocation
import EventKit

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var location: BeachLocationService
    @EnvironmentObject private var calendar: LessonCalendarService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("useLocationOnLaunch") private var useLocationOnLaunch = true
    @AppStorage("distanceUnit") private var distanceUnit = "km"
    @AppStorage("defaultReminder") private var reminder = 60
    @AppStorage("aiEnabled") private var aiEnabled = true
    @State private var name = ""
    @State private var showLogin = false
    @State private var nameSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Text(auth.isAuthenticated ? auth.userInitials : "S")
                            .font(.title.weight(.semibold)).foregroundStyle(SurflyTheme.forecastTeal)
                            .frame(width: 66, height: 66).background(SurflyTheme.softMint, in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(auth.isAuthenticated ? auth.currentUserName : "Welcome to Surfly").font(.headline)
                            Text(auth.currentUserEmail ?? "Explore beaches without an account")
                                .font(.caption).foregroundStyle(SurflyTheme.mutedText).textSelection(.enabled)
                        }
                    }.padding(.vertical, 8)
                    if !auth.isAuthenticated { Button("Sign in or create account") { showLogin = true } }
                }
                if auth.isAuthenticated {
                    Section("Your profile") {
                        TextField("Name", text: $name).textContentType(.name)
                        Button("Save name") {
                            Task { nameSaved = await auth.updateName(name) }
                        }.disabled(auth.isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if nameSaved { Label("Name saved", systemImage: "checkmark.circle").foregroundStyle(SurflyTheme.forecastTeal) }
                        if let error = auth.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                }
                Section("Settings") {
                    Toggle("Find nearby beaches on launch", isOn: $useLocationOnLaunch)
                    Picker("Distance units", selection: $distanceUnit) {
                        Text("Kilometres").tag("km")
                        Text("Miles").tag("mi")
                    }
                    Toggle("Gemini surf suggestions", isOn: $aiEnabled)
                    Picker("Default lesson reminder", selection: $reminder) {
                        Text("None").tag(-1)
                        Text("At start").tag(0)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("1 day before").tag(1440)
                    }
                    Text("Reminders are delivered by Apple Calendar for synced lessons. Forecast-based suggestions remain available when Gemini is off.")
                        .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
                Section("Permissions") {
                    LabeledContent("Location", value: locationStatus)
                    LabeledContent("Calendar", value: calendar.hasFullAccess ? "Read & write" : calendar.authorization == .writeOnly ? "Write only" : "Not connected")
                    Button("Open iOS settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    Text("Your precise location stays on this device except when searching Apple Maps nearby. Forecast requests use the selected beach coordinates.")
                        .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
                Section("About your data") {
                    Text("Lessons, checklists and session history are stored on this device, separately for each signed-in account. They are not yet backed up to the cloud.")
                    Text("Your name and sign-in are managed by Firebase. Apple Maps provides beach search; Open-Meteo provides model forecasts.")
                    Link("Open-Meteo data sources", destination: URL(string: "https://open-meteo.com/en/docs/marine-weather-api")!)
                }.font(.footnote)
                if auth.isAuthenticated {
                    Section {
                        Button("Log out", role: .destructive) {
                            auth.signOut()
                            if !auth.isAuthenticated { dismiss() }
                        }.disabled(auth.isLoading)
                    } footer: { Text("Your local history is kept for your next sign-in on this device.") }
                }
            }
            .scrollContentBackground(.hidden).background(SurflyTheme.background)
            .navigationTitle("My profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { name = auth.currentUserName; location.recheckPermission(); calendar.refreshAuthorization() }
            .onChange(of: auth.currentUserName) { _, value in name = value }
            .onChange(of: name) { _, _ in nameSaved = false }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { location.recheckPermission(); calendar.refreshAuthorization() }
            }
            .sheet(isPresented: $showLogin) { LoginView() }
        }.tint(SurflyTheme.forecastTeal)
    }

    private var locationStatus: String {
        switch location.authorization {
        case .authorizedAlways, .authorizedWhenInUse: location.isApproximate ? "Approximate" : "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not requested"
        }
    }
}
