import SwiftUI
import SwiftData
import FirebaseCore // 1. Importar o Firebase

// 2. Criar o AppDelegate para configurar o Firebase no arranque
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
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
        }
    }
}

