import SwiftUI

enum SurflyTab: Int {
    case forecast = 0
    case map = 1
    case coach = 2
    case analytics = 3
    case schedule = 4
}

struct MainTabView: View {
    @StateObject private var authVM = AuthViewModel()
    @State private var selectedTab: SurflyTab = .forecast
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // TAB 1: Forecast (Home) - Público
            Text("Forecast Home (Próximo Passo)")
                .tabItem {
                    Label("Forecast", systemImage: "water.waves")
                }
                .tag(SurflyTab.forecast)
            
            // TAB 2: Map - Público
            Text("Explore Beaches Map (Próximo Passo)")
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
                featureDescription: "Inicia sessão para acompanhar a evolução das tuas pontuações de postura, horas na água e histórico de sessões.",
                iconName: "chart.bar.xaxis",
                onLoginRedirectToHome: { selectedTab = .forecast }
            ) {
                Text("Analytics & Progress")
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
                Text("My Schedule")
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }
            .tag(SurflyTab.schedule)
        }
        .tint(SurflyTheme.primaryTeal)
        .environmentObject(authVM)
    }
}

#Preview {
    MainTabView()
}