import SwiftUI

struct AuthGateView<Content: View>: View {
    @EnvironmentObject var authVM: AuthViewModel
    let featureTitle: String
    let featureDescription: String
    let iconName: String
    var onLoginRedirectToHome: () -> Void
    @ViewBuilder let content: () -> Content
    
    @State private var showLoginSheet = false
    
    var body: some View {
        if authVM.isAuthenticated {
            content()
        } else {
            VStack(spacing: 20) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(SurflyTheme.softMint)
                        .frame(width: 90, height: 90)
                    Image(systemName: iconName)
                        .font(.system(size: 38))
                        .foregroundColor(SurflyTheme.primaryTeal)
                }
                
                Text(featureTitle)
                    .font(.title2.bold())
                    .foregroundColor(SurflyTheme.darkSlate)
                
                Text(featureDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button {
                    showLoginSheet = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                        Text("Iniciar Sessão ou Criar Conta")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(SurflyTheme.primaryTeal)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SurflyTheme.background.ignoresSafeArea())
            .sheet(isPresented: $showLoginSheet) {
                LoginView(onLoginSuccess: {
                    onLoginRedirectToHome()
                })
                .environmentObject(authVM)
            }
        }
    }
}