import SwiftUI

enum SurflyTheme {
    // Forecast palette from the supplied Home mockup.
    static let forecastTeal = Color(red: 0.055, green: 0.50, blue: 0.50)
    static let deepTeal = Color(red: 0.045, green: 0.39, blue: 0.39)
    static let mutedText = Color(red: 0.38, green: 0.49, blue: 0.50)
    static let cardBorder = Color(red: 0.88, green: 0.92, blue: 0.92)
    // Cores Principais (extraídas do mockup do Figma)
    static let primaryTeal = Color(red: 0.08, green: 0.44, blue: 0.39)     // #147063 - Cartões principais e botões
    static let darkSlate = Color(red: 0.09, green: 0.18, blue: 0.19)       // #172E30 - Dia selecionado e câmara
    static let softMint = Color(red: 0.90, green: 0.96, blue: 0.95)        // #E6F5F2 - Badges e cartões secundários
    static let warmSand = Color(red: 0.96, green: 0.94, blue: 0.90)        // #F5F0E6 - Cartão "Best Time Today"
    static let alertCoral = Color(red: 0.99, green: 0.93, blue: 0.91)      // #FCECE8 - Alerta "Better Spot Nearby"
    static let accentCoralText = Color(red: 0.82, green: 0.31, blue: 0.22) // #D14F38 - Ícone/Texto de alerta
    static let background = Color(red: 0.97, green: 0.98, blue: 0.98)      // #F8FAFA - Fundo geral da app
}
