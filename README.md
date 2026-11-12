# Surfly

Aplicação iOS em SwiftUI para previsões de surf e aprendizagem.

A Forecast Home usa Open-Meteo Marine/Weather, CoreLocation, Gemini através de Firebase AI Logic e EventKit. Não inclui dados meteorológicos de demonstração.

Consultar [inventário completo das alterações, configuração e limitações de validação](docs/FORECAST_HOME.md).

As tabs Explore Beaches, My Schedule e Analytics, a pesquisa mundial de praias e o perfil estão descritos no [inventário desta fase](docs/EXPLORE_SCHEDULE_PROGRESS.md). As sessões/checklists são guardadas neste dispositivo por conta com SwiftData; os analytics usam apenas sessões confirmadas pelo utilizador.

Abrir `surfly.xcodeproj` em macOS com Xcode 26.2 ou superior, resolver os pacotes Firebase e escolher um simulador/dispositivo iOS 26.2+. Para a IA, concluir a ativação Firebase AI Logic/App Check descrita no documento. Open-Meteo não necessita de chave para esta utilização académica não comercial.
