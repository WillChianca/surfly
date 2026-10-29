import Foundation
import SwiftUI
// import FirebaseAuth // Descomentar após adicionar o pacote Firebase no Xcode

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUserEmail: String? = nil
    @Published var currentUserName: String = "Surfista"
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    
    init() {
        // Quando o Firebase estiver ativo:
        // if let user = Auth.auth().currentUser {
        //     self.isAuthenticated = true
        //     self.currentUserEmail = user.email
        // }
    }
    
    func signIn(email: String, password: String) async {
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Por favor, preenche o email e a palavra-passe."
            return
        }
        
        isLoading = true
        
        // Simulação de rede (Substituir por Auth.auth().signIn(withEmail: email, password: password))
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        self.currentUserEmail = email
        self.currentUserName = email.components(separatedBy: "@").first?.capitalized ?? "Surfista"
        self.isAuthenticated = true
        self.isLoading = false
    }
    
    func register(name: String, email: String, password: String, confirmPassword: String) async {
        errorMessage = nil
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "Todos os campos são obrigatórios."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "As palavras-passe não coincidem."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "A palavra-passe deve ter pelo menos 6 caracteres."
            return
        }
        
        isLoading = true
        
        // Simulação de rede (Substituir por Auth.auth().createUser(withEmail: email, password: password))
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        self.currentUserName = name
        self.currentUserEmail = email
        self.isAuthenticated = true
        self.isLoading = false
    }
    
    func signOut() {
        // try? Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUserEmail = nil
    }
    
    var userInitials: String {
        let parts = currentUserName.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(currentUserName.prefix(2)).uppercased()
    }
}