import SwiftUI
import SwiftData
import CoreLocation

enum SurflyTab: Int {
    case forecast = 0
    case map = 1
    case coach = 2
    case analytics = 3
    case schedule = 4
}

struct MainTabView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var beaches = BeachSelectionStore()
    @StateObject private var location = BeachLocationService()
    @StateObject private var calendar = LessonCalendarService()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("useLocationOnLaunch") private var useLocationOnLaunch = true
    @State private var selectedTab: SurflyTab = .forecast
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // TAB 1: Forecast (Home) - Público
            ForecastHomeView(onExploreMap: { selectedTab = .map })
                .tabItem {
                    Label("Forecast", systemImage: "water.waves")
                }
                .tag(SurflyTab.forecast)
            
            // TAB 2: Map - Público
            ExploreBeachesView(onForecast: { selectedTab = .forecast })
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(SurflyTab.map)
            
            // TAB 3: Pose Coach (Câmara IA) - Requer Autenticação
            AuthGateView(
                featureTitle: "AI Pose Coach",
                featureDescription: "Inicia sessão para gravar o teu pop-up, analisar os 33 pontos biomecânicos do teu corpo e receber feedback em tempo real.",
                iconName: "figure.surfing",
                onLoginRedirectToHome: { selectedTab = .forecast }
            ) {
                Text("AI Pose Coach Camera")
            }
            .tabItem {
                Label("Coach", systemImage: "figure.surfing")
            }
            .tag(SurflyTab.coach)
            
            // TAB 4: Analytics - Requer Autenticação
            AuthGateView(
                featureTitle: "My Surf Journey",
                featureDescription: "Inicia sessão para acompanhar as aulas realizadas, horas na água e histórico de sessões.",
                iconName: "chart.bar.xaxis",
                onLoginRedirectToHome: { selectedTab = .forecast }
            ) {
                AnalyticsView()
            }
            .tabItem {
                Label("Analytics", systemImage: "chart.bar.xaxis")
            }
            .tag(SurflyTab.analytics)
            
            // TAB 5: Schedule (Calendário) - Requer Autenticação
            AuthGateView(
                featureTitle: "My Schedule",
                featureDescription: "Inicia sessão para sincronizar as tuas aulas de surf e o checklist de equipamento diretamente com o Apple Calendar.",
                iconName: "calendar",
                onLoginRedirectToHome: { selectedTab = .forecast }
            ) {
                MyScheduleView()
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }
            .tag(SurflyTab.schedule)
        }
        .tint(SurflyTheme.primaryTeal)
        .environmentObject(authVM)
        .environmentObject(beaches)
        .environmentObject(location)
        .environmentObject(calendar)
        .preferredColorScheme(.light)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
            if useLocationOnLaunch { beaches.followsLocation = true; location.request() }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                location.recheckPermission()
                if beaches.followsLocation, location.location == nil, !location.isLocating,
                   location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways { location.request() }
            }
        }
        .task(id: location.fixID) {
            if beaches.followsLocation, let fix = location.location { await beaches.findNearest(to: fix) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                location.recheckPermission()
                calendar.refreshAuthorization()
                if beaches.followsLocation, location.location == nil, !location.isLocating,
                   location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways { location.request() }
            }
        }
        .onChange(of: authVM.userID) { old, new in
            if old != nil && new != old { selectedTab = .forecast; calendar.error = nil }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: SurfLesson.self, inMemory: true)
}
