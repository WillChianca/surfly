import SwiftUI

struct SurflyCard<Content: View>: View {
    var color: Color = .white
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(color, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(SurflyTheme.cardBorder, lineWidth: 1))
    }
}

struct SurflyPageHeader: View {
    let eyebrow: String
    let title: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(SurflyTheme.forecastTeal)
                Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(SurflyTheme.darkSlate)
            }
            Spacer(minLength: 8)
            ProfileButton()
        }
    }
}

struct ProfileButton: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showProfile = false
    var body: some View {
        Button { showProfile = true } label: {
            Group {
                if auth.isAuthenticated { Text(auth.userInitials).font(.caption.weight(.semibold)) }
                else { Image(systemName: "person") }
            }.foregroundStyle(SurflyTheme.forecastTeal).frame(width: 44, height: 44)
                .background(SurflyTheme.warmSand, in: Circle())
        }
        .accessibilityLabel("Profile and settings")
        .sheet(isPresented: $showProfile) { ProfileView() }
    }
}
