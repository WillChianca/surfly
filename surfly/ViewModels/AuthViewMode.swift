import Foundation
import Combine
import SwiftUI
import FirebaseAuth

@MainActor
class AuthViewModel: ObservableObject {
    
    @Published var isAuthenticated: Bool = false
    @Published var currentUserEmail: String? = nil
    @Published var currentUserName: String = "Surfista"
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    
    init(preview: Bool = false) {
        guard !preview, ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        if let user = Auth.auth().currentUser {
             self.isAuthenticated = true
             self.currentUserEmail = user.email
             self.currentUserName = user.displayName ?? user.email?.components(separatedBy: "@").first?.capitalized ?? "Surfista"
        }
    }
    
    func signIn(email: String, password: String) async {
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Por favor, preenche o email e a palavra-passe."
            return
        }
        
        isLoading = true
        
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUserEmail = result.user.email
            currentUserName = result.user.displayName ?? email.components(separatedBy: "@").first?.capitalized ?? "Surfista"
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
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
        
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let profile = result.user.createProfileChangeRequest()
            profile.displayName = name
            do { try await profile.commitChanges() }
            catch { errorMessage = "Conta criada, mas não foi possível guardar o nome: \(error.localizedDescription)" }
            currentUserName = result.user.displayName ?? name
            currentUserEmail = result.user.email
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            isAuthenticated = false
            currentUserEmail = nil
            currentUserName = "Surfista"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    var userInitials: String {
        let parts = currentUserName.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(currentUserName.prefix(2)).uppercased()
    }
}
