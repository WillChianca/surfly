import SwiftUI
import CoreLocation

struct ForecastHomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = ForecastViewModel()
    @StateObject private var location = BeachLocationService()
    @State private var showBeaches = false
    @State private var showLogin = false
    @State private var showLesson = false
    @State private var showSources = false
    @State private var followsLocation = true
    @State private var calendarConfirmation = false
    @State private var lessonAfterLogin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let message = location.message {
                        Text(message).font(.caption).foregroundStyle(SurflyTheme.mutedText)
                    }
                    daySelector
                    if model.isLoading {
                        statusCard(title: "Reading the ocean…", message: "Fetching the latest marine and weather forecasts.", loading: true)
                    } else if let error = model.error {
                        statusCard(title: "Forecast unavailable", message: error, loading: false)
                        Button("Try again") { model.refreshID = UUID() }.buttonStyle(ForecastPrimaryButton())
                    } else if model.forecast != nil {
                        conditionsCard
                        advisorCard
                        nearbyCard
                        Button {
                            if auth.isAuthenticated {
                                showLesson = true
                            } else {
                                lessonAfterLogin = true
                                showLogin = true
                            }
                        } label: {
                            Label("Have a Surf Lesson? Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(ForecastPrimaryButton())
                        sourcesFooter
                    } else {
                        statusCard(title: location.isLocating ? "Finding your beach…" : "Find your forecast",
                                   message: "Choose a beach or use your location to find the closest beach in our regional catalogue.",
                                   loading: location.isLocating)
                        Button("Choose a beach") { showBeaches = true }.buttonStyle(ForecastPrimaryButton())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(SurflyTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load(refresh: true) }
            .task {
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                location.request()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    if let fetched = model.forecast?.fetchedAt, Date().timeIntervalSince(fetched) >= 900,
                       !model.isLoading, !model.isComparing {
                        model.refreshID = UUID()
                    } else if let window = model.advice?.window, window.start < Date() {
                        model.updateAdvice()
                    }
                }
            }
            .task(id: "\(model.beach?.id ?? "none")-\(model.refreshID)") { await model.load() }
            .onChange(of: location.location) { _, fix in
                if followsLocation, let fix { model.chooseNearest(to: fix) }
            }
            .onChange(of: model.selectedDay) { _, _ in model.updateAdvice() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let fetched = model.forecast?.fetchedAt, Date().timeIntervalSince(fetched) >= 900 {
                    model.refreshID = UUID()
                }
            }
            .sheet(isPresented: $showBeaches) { beachPicker }
            .sheet(isPresented: $showLogin, onDismiss: {
                if lessonAfterLogin && auth.isAuthenticated { showLesson = true }
                lessonAfterLogin = false
            }) { LoginView() }
            .sheet(isPresented: $showLesson) {
                if let beach = model.beach {
                    LessonScheduleView(beach: beach, day: model.selectedDay, advice: model.advice,
                                       forecast: model.forecast) { calendarConfirmation = true }
                }
            }
            .sheet(isPresented: $showSources) { ForecastSourcesView(forecast: model.forecast) }
            .alert("Lesson saved", isPresented: $calendarConfirmation) {
                Button("Done", role: .cancel) { }
            } message: { Text("Your lesson and reminder were added to Apple Calendar.") }
        }
        .tint(SurflyTheme.forecastTeal)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "water.waves").font(.title2).foregroundStyle(SurflyTheme.forecastTeal)
            Button { showBeaches = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(followsLocation && location.location != nil ? "Closest listed beach" : "Selected beach", systemImage: "location.fill")
                        .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                    Text(model.beach.map { "\($0.name) / \($0.region)" } ?? "Choose your beach")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(SurflyTheme.darkSlate)
                        .multilineTextAlignment(.leading)
                    if let fix = location.location, let beach = model.beach {
                        Text(String(format: "%.1f km · straight-line distance", fix.distance(from: beach.location) / 1000))
                            .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                    } else {
                        Text("Portugal · West coast").font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                    }
                }
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            if auth.isAuthenticated {
                Text(auth.userInitials)
                    .font(.caption.weight(.semibold)).foregroundStyle(SurflyTheme.forecastTeal)
                    .frame(width: 42, height: 42).background(SurflyTheme.warmSand, in: Circle())
                    .accessibilityLabel(auth.currentUserName)
            } else {
                Button { showLogin = true } label: {
                    Image(systemName: "person").font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44).background(SurflyTheme.warmSand, in: Circle())
                }.accessibilityLabel("Sign in")
            }
        }
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.days, id: \.self) { day in
                    let selected = ForecastClock.calendar.isDate(day, inSameDayAs: model.selectedDay)
                    Button { model.selectedDay = day } label: {
                        VStack(spacing: 5) {
                            Text(ForecastClock.text(day, format: "EEE")).font(.caption)
                            Text(ForecastClock.text(day, format: "d")).font(.headline)
                        }
                        .foregroundStyle(selected ? .white : SurflyTheme.darkSlate)
                        .frame(width: 58, height: 58)
                        .background(selected ? SurflyTheme.darkSlate : .white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ForecastClock.text(day, format: "EEEE d MMMM"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Beginner Friendly Score").font(.subheadline)
                Spacer()
                Button { showSources = true } label: { Image(systemName: "sparkles") }
                    .accessibilityLabel("How the score is calculated")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) { scoreNumber; scoreBadge }
                VStack(alignment: .leading, spacing: 8) { scoreNumber; scoreBadge }
            }
            Text(scoreDescription).font(.subheadline)
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { metrics }
                VStack(alignment: .leading, spacing: 16) { metrics }
            }
            if let hour = model.displayHour {
                Text("Forecast for \(ForecastClock.text(hour.time, format: "EEE d MMM · HH:mm")) · Lisbon time")
                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [SurflyTheme.forecastTeal, SurflyTheme.deepTeal], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22))
    }

    private var scoreNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(model.score.map(String.init) ?? "—").font(.system(size: 50, weight: .bold, design: .rounded))
            if model.score != nil { Text("%").font(.title3.weight(.bold)) }
        }.accessibilityLabel(model.score.map { "Computed suitability index: \($0) percent" } ?? "Score unavailable")
    }

    private var scoreBadge: some View {
        Label(model.score.map { $0 >= 75 ? "More favourable" : $0 >= 60 ? "Mixed conditions" : "Challenging" } ?? "Insufficient data",
              systemImage: (model.score ?? 0) >= 75 ? "checkmark" : "info.circle")
            .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.14), in: Capsule())
    }

    private var scoreDescription: String {
        guard let score = model.score else { return "A complete wave and wind forecast is needed to calculate this index." }
        if score >= 75 { return "Gentler forecast conditions. Plan your session with an instructor." }
        if score >= 60 { return "Some conditions need care. Check the beach with your instructor." }
        return "Demanding conditions for beginners. Consider a land-based lesson."
    }

    @ViewBuilder private var metrics: some View {
        metric("Wave Size", icon: "water.waves", value: ForecastEngine.waveDescription(model.displayHour?.waveHeight),
               detail: model.displayHour?.waveHeight.map { String(format: "%.1f m · model", $0) } ?? "Unavailable")
        metric("Wind", icon: "wind", value: windLabel,
               detail: model.displayHour?.windSpeed.map { String(format: "%.0f km/h", $0) } ?? "Unavailable")
        metric("Water", icon: "thermometer.medium", value: model.displayHour?.waterTemperature.map { String(format: "%.1f°C", $0) } ?? "—",
               detail: "Sea surface")
    }

    private var windLabel: String {
        guard let hour = model.displayHour, let beach = model.beach else { return "Unavailable" }
        return ForecastEngine.windDescription(hour, beach: beach)
    }

    private func metric(_ title: String, icon: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(.white.opacity(0.8))
            Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.9))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advisorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(SurflyTheme.forecastTeal)
                    .padding(9).background(SurflyTheme.softMint, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Surf Advisor").font(.headline)
                    Text(model.advice?.isAI == true ? "Gemini · based on this forecast" : "For your beginner surf session")
                        .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
                Spacer(minLength: 0)
                if model.isAdvising { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(model.advice?.isAI == true ? "Best Time · AI selection" : "Forecast-based window", systemImage: "sun.max")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    if model.advice?.window != nil { Text("2 hr").font(.caption2).foregroundStyle(SurflyTheme.mutedText) }
                }
                Text(model.advice?.window?.label ?? (model.isComparing ? "Checking forecasts…" : "No suitable window found"))
                    .font(.title3.weight(.bold))
                if model.advice?.window == nil && !model.isComparing {
                    Text("No complete, favourable two-hour daylight window remains for this day.")
                        .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(SurflyTheme.warmSand, in: RoundedRectangle(cornerRadius: 14))
            if let advice = model.advice, !advice.gear.isEmpty {
                Text("What to Bring").font(.caption.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(advice.gear) { item in
                        Text(item.label).font(.caption2.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(SurflyTheme.softMint, in: Capsule())
                    }
                }
                Text("Equipment suggestions · confirm fit and warmth with your instructor.")
                    .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
            }
            if let error = model.advisorError {
                Text(error).font(.caption).foregroundStyle(SurflyTheme.mutedText)
                Button("Retry AI advisor") { model.updateAdvice() }.font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(SurflyTheme.darkSlate)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(SurflyTheme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder private var nearbyCard: some View {
        if let better = model.betterSpot, let beach = model.beach {
            Button { followsLocation = false; model.beach = better.beach } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(SurflyTheme.accentCoralText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Better Spot Nearby: \(better.beach.name)").font(.caption.weight(.semibold))
                        Text(String(format: "%.1f km from %@ · a higher computed score in the same window.",
                                    beach.location.distance(from: better.beach.location) / 1000, beach.name))
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(SurflyTheme.darkSlate).padding(14)
                    .background(SurflyTheme.alertCoral, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        } else if model.isComparing {
            Label("Checking nearby beaches…", systemImage: "mappin.and.ellipse")
                .font(.caption).foregroundStyle(SurflyTheme.mutedText)
        }
        if let error = model.comparisonError { Text(error).font(.caption).foregroundStyle(SurflyTheme.mutedText) }
    }

    private var sourcesFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let forecast = model.forecast {
                Text("Retrieved \(ForecastClock.text(forecast.fetchedAt, format: "d MMM · HH:mm")) · Lisbon time")
            }
            Text("Model forecasts, not beach observations. The score is an experimental planning index; check local conditions with an instructor.")
            Button("Open-Meteo & model providers · Data and score details") { showSources = true }
        }.font(.caption2).foregroundStyle(SurflyTheme.mutedText)
    }

    private func statusCard(title: String, message: String, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading { ProgressView().tint(SurflyTheme.forecastTeal) }
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(SurflyTheme.darkSlate)
            Text(message).font(.subheadline).foregroundStyle(SurflyTheme.mutedText)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private var beachPicker: some View {
        NavigationStack {
            List {
                Button {
                    followsLocation = true
                    location.request()
                    showBeaches = false
                } label: { Label("Use my location", systemImage: "location") }
                Section("Regional beach catalogue") {
                    ForEach(SurfBeach.catalogue) { beach in
                        Button {
                            followsLocation = false
                            model.beach = beach
                            showBeaches = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(beach.name).foregroundStyle(SurflyTheme.darkSlate)
                                    Text(beach.region).font(.caption).foregroundStyle(SurflyTheme.mutedText)
                                }
                                Spacer()
                                if beach.id == model.beach?.id { Image(systemName: "checkmark") }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Choose a beach")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showBeaches = false } } }
        }.presentationDragIndicator(.visible)
    }
}

struct ForecastPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 10)
            .background(SurflyTheme.forecastTeal.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ForecastSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    let forecast: BeachForecast?
    var body: some View {
        NavigationStack {
            List {
                Section("Forecast data") {
                    Text("Open-Meteo Marine and Weather APIs. Wave and weather models include ECMWF, DWD, Météo-France, Copernicus Marine and NOAA. Best Match can combine providers; the response does not identify a single model per value.")
                    Link("Marine data and model providers", destination: URL(string: "https://open-meteo.com/en/docs/marine-weather-api")!)
                    Link("Weather data and model providers", destination: URL(string: "https://open-meteo.com/en/docs")!)
                    Link("Data licence · CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    if let forecast {
                        Text(String(format: "Marine grid: %.4f, %.4f. Nearby beaches may share a grid cell.", forecast.marineLatitude, forecast.marineLongitude))
                    }
                    Text("Wave height is significant offshore model height. Body-height labels are approximate; they do not predict the size of breaking waves at this beach. Sea-surface temperature is modelled, not a thermometer reading.")
                }
                Section("Beginner index · experimental v1") {
                    Text("Weighted score: wave height 60%, wind speed 25%, wave period 15%. Onshore wind can reduce the score. Large waves, strong wind/gusts or energetic swell cap it at 25%. Missing required values mean no score.")
                    Text("These are product rules, not a validated probability of safety. Tides, currents, seabed, crowds, beach flags and lifeguard coverage are not evaluated. Local instruction is essential.")
                    Text("A two-hour window needs three consecutive daytime samples, all scoring at least 60, ending before sunset. Nearby suggestions require an improvement of at least 10 points at matching timestamps, within 25 km of the selected beach.")
                }
                Section("AI and privacy") {
                    Text("Gemini via Firebase AI Logic selects only validated time windows and equipment IDs. Forecast measurements and the beach name are sent to Google. Your device location, email and calendar notes are not included in the prompt.")
                    Text("If AI is unavailable, the app clearly labels its local forecast-based suggestion. Wetsuit thickness is a recommendation, not an observed measurement. Board size is left to your instructor.")
                }
            }.font(.subheadline)
                .navigationTitle("Data & methodology")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview {
    // No fabricated forecast fixtures. The initial view contains only the empty/loading state.
    ForecastHomeView().environmentObject(AuthViewModel(preview: true))
}
