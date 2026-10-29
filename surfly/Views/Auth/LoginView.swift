import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    
    var onLoginSuccess: (() -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Cabeçalho com Identidade Visual Surfly
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(SurflyTheme.softMint)
                                .frame(width: 84, height: 84)
                            
                            Image(systemName: "water.waves")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(SurflyTheme.primaryTeal)
                        }
                        
                        Text("Bem-vindo ao Surfly")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(SurflyTheme.darkSlate)
                        
                        Text("Inicia sessão para analisar a tua postura com IA, agendar aulas e acompanhar a tua evolução.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 24)
                    
                    // Formulário
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EMAIL")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundColor(.secondary)
                                TextField("teu.email@exemplo.com", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PALAVRA-PASSE")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: "lock")
                                    .foregroundColor(.secondary)
                                SecureField("••••••••", text: $password)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        
                        if let error = authVM.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .font(.caption)
                            .foregroundColor(SurflyTheme.accentCoralText)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SurflyTheme.alertCoral)
                            .cornerRadius(10)
                        }
                    }
                    
                    // Botão Principal de Login
                    Button {
                        Task {
                            await authVM.signIn(email: email, password: password)
                            if authVM.isAuthenticated {
                                onLoginSuccess?()
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if authVM.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Iniciar Sessão")
                                    .font(.headline)
                                Image(systemName: "arrow.right")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(SurflyTheme.primaryTeal)
                        .cornerRadius(16)
                    }
                    .disabled(authVM.isLoading)
                    
                    // Link para Registo
                    HStack(spacing: 4) {
                        Text("Ainda não tens conta?")
                            .foregroundColor(.secondary)
                        Button("Criar conta") {
                            showRegister = true
                        }
                        .fontWeight(.bold)
                        .foregroundColor(SurflyTheme.primaryTeal)
                    }
                    .font(.subheadline)
                }
                .padding(24)
            }
            .background(SurflyTheme.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(onRegisterSuccess: {
                    onLoginSuccess?()
                    dismiss()
                })
            }
        }
    }
}