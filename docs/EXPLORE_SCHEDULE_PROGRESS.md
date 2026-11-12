# Explore, Schedule, Progress e Perfil

Implementação de 12/11/2026, a partir do relatório e mockups fornecidos. Este documento complementa e atualiza `FORECAST_HOME.md` nas áreas alteradas nesta fase.

## Funcionalidades

### Explore Beaches

- Mapa real Apple Maps/MapKit, com localização do dispositivo, bússola, escala, praias e cartão de seleção.
- Pesquisa por nome e país através de `MKLocalSearch`, sem a restrição às cinco praias iniciais. Pesquisa na área visível ao mover o mapa.
- Seleção livre de um ponto costeiro no centro do mapa, com nome introduzido pelo utilizador, para praias que a pesquisa não encontra. Esse ponto é identificado como escolha do utilizador, não como praia verificada.
- Favoritos, locais recentes e seleção persistem neste dispositivo. Mapa, Home e escolha de praia para aulas usam o mesmo modelo de praia.
- Pins mostram índices apenas depois de receber previsões reais. Sem dados, mostram um traço. A Home continua a explicar a fórmula experimental.
- Distâncias calculadas por CoreLocation; direções reais podem ser abertas em Apple Maps a partir de uma aula. Não há minutos de viagem inventados.
- MapKit não fornece um catálogo exaustivo de todas as praias do mundo. A seleção manual cobre locais não indexados; a previsão continua dependente da cobertura marinha Open-Meteo. Praias de água doce não são suportadas pela previsão marinha.

### Localização e horas

- Uma única instância de CLLocationManager partilhada, com autorização em utilização, timeout, rejeição de fix inválido/antigo/impreciso e indicação de localização aproximada.
- Revogação da autorização remove a posição da interface. Alterações manuais de praia invalidam o resultado de uma procura GPS pendente.
- Procura próxima até 25 km; não escolhe automaticamente uma praia portuguesa distante quando o utilizador está noutro país.
- Posições com mais de cinco minutos deixam de ser usadas. Em modo de localização, a app solicita uma nova posição enquanto está ativa; o temporizador cancela quando a vista termina.
- Os dois endpoints Open-Meteo usam `timezone=auto`, preservam timestamps Unix e apresentam os dias/horários no fuso devolvido pela API.
- Praias novas não recebem orientações da costa inventadas: apresentam vento por ponto cardeal e omitem a penalização onshore no índice quando a orientação é desconhecida.
- Pontos a mais de 50 km da célula marinha devolvida são recusados. Este limite evita associações muito distantes, mas não certifica que o ponto é uma praia ou local de surf.

### My Schedule

- Modelo SwiftData persistente `SurfLesson`, separado por UID Firebase. Aulas locais funcionam mesmo sem acesso ao Calendário.
- Seletor semanal, aulas do dia, futuras e sessões passadas por confirmar; criação a partir da Home ou do Schedule.
- Formulário com data/horário, praia pesquisada, instrutor, notas, opção de sincronização e lembrete.
- Ligação opcional a Apple Calendar com acesso de escrita para adicionar; acesso completo apenas para ler alterações, editar, cancelar eventos ligados e importar.
- Acesso completo solicitado por uma ação explícita na app. Não são automaticamente importados todos os eventos pessoais.
- Importação explícita de eventos com “surf” no título e localização geográfica, no intervalo de um ano anterior a um ano futuro. Os eventos antigos criados pela Home podem ser selecionados aqui.
- Releitura dos eventos ligados ao entrar na tab, regressar à app ou receber `EKEventStoreChanged`. Identificador estável no URL `surfly://lesson/<UUID>` permite recuperar ligações de eventos criados nesta versão caso o identificador EventKit mude.
- Um evento não encontrado não apaga a aula: fica um aviso para verificar o Calendário. Um evento importado mantém o identificador original; se esse identificador mudar e não tiver URL Surfly, poderá ser necessário voltar a ligar o evento.
- Alterações externas de hora/praia invalidam o checklist anterior. Uma atualização da previsão só guarda sugestões para o intervalo realmente coberto.
- Checklist com estado “preparado” persistente; não é perdido ao mudar de tab ou reiniciar a app.
- Edição de eventos sincronizados através do editor nativo EventKitUI. Aulas apenas locais têm formulário de edição de datas, instrutor e notas; uma mudança de horário invalida o snapshot da previsão e o checklist.
- Cancelamento explícito remove o evento ligado e marca a aula local como cancelada. Não conta para os analytics.

### Analytics & Progress

- Total de aulas realizadas, minutos/horas realmente registados, sequência semanal, gráfico de tempo na água das últimas oito semanas, histórico e praia mais frequentada.
- Uma aula agendada ou passada não é contada automaticamente como realizada. O utilizador confirma a sessão e introduz minutos reais; a duração planeada não é utilizada como tempo na água.
- Registos podem ser corrigidos ou ter a conclusão desfeita. Contadores/gráfico atualizam através de SwiftData.
- Sem sessões: estado vazio e totais zero. Sem AI Coach: explicação no painel de postura, sem scores ou gráfico de postura fictícios.
- Totais/histórico são por conta; o gráfico e a sequência semanal usam o calendário do dispositivo, explicitamente por semanas de segunda a domingo. Datas individuais da sessão mantêm o fuso da praia.

### Perfil e Settings

- O avatar no canto superior direito abre o perfil na Home, Map, Schedule e Analytics.
- Nome/email reais do Firebase; alteração de nome e logout real. Sem sessão: acesso a login e definições públicas.
- Definições funcionais: procurar praias por GPS ao arrancar, distâncias km/milhas, ativar/desativar Gemini e lembrete predefinido de aulas.
- Estado das permissões e botão para as definições iOS. O toggle de lembrete refere-se ao Apple Calendar, não a notificações locais fictícias.
- Histórico/checklists ficam neste dispositivo por conta; ainda não há backup/cloud sync do SwiftData. Favoritos/recentes e preferências públicas são partilhados no dispositivo.

## Inventário completo desta fase

Alterados:

- `surfly/App/MainTabView.swift`: liga as novas tabs, objetos partilhados, localização e transições de sessão.
- `surfly/surflyApp.swift`: container SwiftData.
- `surfly/Models/Forecast.swift`: praias Codable, orientação opcional e timezone de praia/previsão.
- `surfly/Services/Forecast/OpenMeteoService.swift`: timezone automático e validação da célula marinha.
- `surfly/Services/Forecast/ForecastEngine.swift`: direção de vento sem orientação conhecida e janelas no fuso correto.
- `surfly/Services/Forecast/BeachLocationService.swift`: validade do GPS, autorizações, precisão e cancelamento.
- `surfly/ViewModels/ForecastViewModel.swift`: pesquisa online de praias próximas, timezone e toggle Gemini.
- `surfly/ViewModels/AuthViewMode.swift`: UID, observação da sessão e edição de nome.
- `surfly/Views/Forecast/ForecastHomeView.swift`: seleção partilhada, pesquisa global, perfil, unidades e horários.
- `surfly/Views/Forecast/LessonScheduleView.swift`: persistência local, sincronização opcional e snapshots meteorológicos válidos.
- `surfly.xcodeproj/project.pbxproj`: descrição de acesso completo a Calendário em Debug e Release.
- `surflyTests/ForecastTests.swift`: contrato atualizado para timezone automático, rejeição de células marinhas distantes e validade dos snapshots de aulas.
- `scripts/verify_live_forecast.py`: verificação mundial opcional e timezone resolvido pelo fornecedor.
- `README.md`: ligação à documentação desta fase.

Adicionados:

- `surfly/Models/SurfLesson.swift`
- `surfly/Services/Beaches/BeachDiscoveryService.swift`
- `surfly/Services/Calendar/LessonCalendarService.swift`
- `surfly/ViewModels/BeachSelectionStore.swift`
- `surfly/Core/Components/AppSettings.swift`
- `surfly/Core/Components/SurflyCards.swift`
- `surfly/Views/Map/BeachSearchView.swift`
- `surfly/Views/Map/ExploreBeachesView.swift`
- `surfly/Views/Schedule/MyScheduleView.swift`
- `surfly/Views/Schedule/LessonDetailView.swift`
- `surfly/Views/Analytics/AnalyticsView.swift`
- `surfly/Views/Profile/ProfileView.swift`
- `surflyTests/JourneyTests.swift`
- `docs/EXPLORE_SCHEDULE_PROGRESS.md`

Nenhuma dependência externa nova da app: MapKit, CoreLocation, EventKit, EventKitUI, SwiftData e Charts são frameworks Apple. Mantêm-se os pacotes Firebase existentes. Não é preciso uma chave Apple Maps para MapKit nativo. A ativação Gemini/App Check pendente da fase anterior não bloqueia estas novas tabs.

## Validação

Ambiente atual: Windows, sem Xcode, SDK iOS ou compilador Swift. A compilação iOS, testes XCTest, interação GPS real, pesquisa MapKit, calendário e comparação visual com o mockup precisam de ser executados em macOS/iPhone. Não considerar “GPS validado num dispositivo” apenas por existirem testes de lógica.

Testes adicionados cobrem isolamento de contas, persistência SwiftData/checklist, exclusão de aulas planeadas/canceladas, sequência semanal na mudança de ano, validade temporal de uma sessão, GPS inválido/antigo/impreciso, corrida entre pesquisa GPS e escolha manual, ausência de fallback distante, favoritos/recentes, timezone estrangeiro e conversão real de milhas.

Verificação de APIs executada: `python scripts/verify_live_forecast.py --global-probes` passou nas sete localizações em 12/11/2026 às 18:12 UTC. Cada localização devolveu 168 horas coincidentes nas APIs meteorológica/marinha e temperaturas de água; os fusos resolvidos foram Europe/Lisbon, Australia/Sydney e Pacific/Honolulu. Os dois pontos internacionais são apenas sondas de teste e não entram no catálogo da app. Respostas locais: `tmp/forecast-verification/verification.json` e JSONs associados (ignorados pelo Git).

Verificação de sintaxe dos 32 ficheiros Swift com tree-sitter-swift: sem erros. `git diff --check`: sem erros de whitespace. Estas verificações não substituem compilação, typecheck, XCTest ou teste visual iOS. Existem 23 testes unitários de Forecast/Journey no código, por executar no Xcode.

No Mac: resolver os pacotes e executar o target surflyTests conforme `FORECAST_HOME.md`. Depois verificar num iPhone/simulador: GPS permitido/negado/aproximado, mudança de permissões, pesquisa de uma praia estrangeira, pin manual, troca rápida de praia, criação com/sem acesso ao calendário, importação de evento anterior, mudança de data no calendário, checklist após reinício, registo/edição de duração real, logout/login noutra conta e nome atualizado.

Referências: [MapKit search](https://developer.apple.com/documentation/mapkit/mklocalsearch), [timezone do local](https://developer.apple.com/documentation/mapkit/mkmapitem/timezone), [EventKit](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui), [Open-Meteo](https://open-meteo.com/en/docs).
