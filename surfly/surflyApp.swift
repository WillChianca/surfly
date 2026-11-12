import SwiftUI
import SwiftData
import FirebaseCore // 1. Importar o Firebase
import FirebaseAppCheck

// 2. Criar o AppDelegate para configurar o Firebase no arranque
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
        // Register the simulator token in Firebase App Check; never commit the token.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif
        // Release uses Firebase App Check's default DeviceCheck provider.
        FirebaseApp.configure()
        return true
    }
}

@main
struct surflyApp: App {
    // 3. Ligar o AppDelegate ao ciclo de vida do SwiftUI
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(for: SurfLesson.self)
        }
    }
}

