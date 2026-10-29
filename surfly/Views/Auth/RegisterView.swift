import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    var onRegisterSuccess: (() -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CREATE ACCOUNT")
                        .font(.caption.weight(.bold))
                        .foregroundColor(SurflyTheme.primaryTeal)
                    
                    Text("Começa a tua jornada no surf")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(SurflyTheme.darkSlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                
                VStack(spacing: 16) {
                    inputField(title: "NOME", icon: "person", placeholder: "Wilton Junior", text: $name)
                    inputField(title: "EMAIL", icon: "envelope", placeholder: "teu.email@exemplo.com", text: $email, isEmail: true)
                    secureInputField(title: "PALAVRA-PASSE", placeholder: "Mínimo 6 caracteres", text: $password)
                    secureInputField(title: "CONFIRMAR PALAVRA-PASSE", placeholder: "Repete a palavra-passe", text: $confirmPassword)
                    
                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(SurflyTheme.accentCoralText)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SurflyTheme.alertCoral)
                            .cornerRadius(10)
                    }
                }
                
                Button {
                    Task {
                        await authVM.register(name: name, email: email, password: password, confirmPassword: confirmPassword)
                        if authVM.isAuthenticated {
                            onRegisterSuccess?()
                        }
                    }
                } label: {
                    HStack {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Criar Conta e Entrar")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SurflyTheme.primaryTeal)
                    .cornerRadius(16)
                }
                .disabled(authVM.isLoading)
            }
            .padding(24)
        }
        .background(SurflyTheme.background.ignoresSafeArea())
    }
    
    private func inputField(title: String, icon: String, placeholder: String, text: Binding<String>, isEmail: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            HStack {
                Image(systemName: icon).foregroundColor(.secondary)
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(isEmail ? .never : .words)
                    .keyboardType(isEmail ? .emailAddress : .default)
                    .autocorrectionDisabled()
            }
            .padding()
            .background(Color.white)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }
    
    private func secureInputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            HStack {
                Image(systemName: "lock").foregroundColor(.secondary)
                SecureField(placeholder, text: text)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }
}