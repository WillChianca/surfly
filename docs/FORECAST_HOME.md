# Forecast Home - implementação e revisão

## Âmbito

Implementação nativa SwiftUI da Home e do modal de agendamento que a Home abre, baseada no relatório individual e nas imagens fornecidas. A interface mantém o inglês do mockup. As restantes tabs mantêm o âmbito anterior.

Os números do mockup não foram copiados para a app. A Home não tem fixtures meteorológicas, modos de demonstração ou valores de fallback. As previsões são dados de modelos Open-Meteo, não observações em tempo real na praia. O índice percentual e o equipamento são recomendações calculadas, com metodologia visível.

## Ficheiros alterados

| Ficheiro | Alteração |
| --- | --- |
| `surfly/App/MainTabView.swift` | Substitui o placeholder Forecast por `ForecastHomeView`. |
| `surfly/Core/Theme/SurflyTheme.swift` | Acrescenta a paleta Home: teal, teal escuro, texto secundário e contornos. |
| `surfly/surflyApp.swift` | Configura Firebase App Check Debug antes de Firebase em builds Debug; Release usa DeviceCheck por omissão. |
| `surfly/ViewModels/AuthViewMode.swift` | Corrige o login/registo que antes marcava sucesso após erro do Firebase, guarda o nome e executa logout real. Necessário para o perfil e acesso ao agendamento. Preview sem sessão inventada. |
| `surfly.xcodeproj/project.pbxproj` | Liga FirebaseAILogic e FirebaseAppCheck do pacote 13.1.1 já existente; adiciona descrições de localização em utilização e acesso ao calendário apenas para escrita, em Debug/Release. |
| `README.md` | Instruções de execução e ligação a este documento. |

## Ficheiros adicionados

| Ficheiro | Responsabilidade |
| --- | --- |
| `surfly/Models/Forecast.swift` | Praias, horas de previsão, janelas, equipamento e timezone Europe/Lisbon. |
| `surfly/Services/Forecast/OpenMeteoService.swift` | Pedidos HTTPS, validação de unidades, valores opcionais, junção por timestamp e cache em memória de 15 minutos. |
| `surfly/Services/Forecast/ForecastEngine.swift` | Índice experimental, vento relativo à orientação da praia, janela diurna e sugestões de equipamento. |
| `surfly/Services/Forecast/BeachLocationService.swift` | CoreLocation, permissões, timeout, precisão e posição recente. |
| `surfly/Services/Forecast/SurfAdvisorService.swift` | Gemini via Firebase AI Logic, JSON restrito e validação dos IDs. |
| `surfly/ViewModels/ForecastViewModel.swift` | Carregamento, cancelamento, seleção dos dias, comparação próxima e estado do advisor. |
| `surfly/Views/Forecast/ForecastHomeView.swift` | Layout, seletor de praia/dia, cartões, fontes/metodologia, loading/erro/vazio, pull-to-refresh. |
| `surfly/Views/Forecast/LessonScheduleView.swift` | Modal com horários, praia, instrutor, notas, checklist, lembrete e gravação EventKit. |
| `surflyTests/ForecastTests.swift` | Casos de ausência de dados, unidades, timestamps, janelas, condições exigentes, validação da IA e timezone. Valores sintéticos apenas no target de testes. |
| `scripts/verify_live_forecast.py` | Verifica respostas reais dos dois endpoints nas cinco praias; guarda evidência em `tmp`, nunca utilizada pela app. |
| `.gitignore` | Exclui evidência temporária e DerivedData. |
| `docs/FORECAST_HOME.md` | Este inventário, decisões, configuração e validação. |

## Design e comportamento

- Fundo claro, cartão principal teal com gradiente, dia selecionado escuro, advisor branco, janela areia, chips menta e alerta coral.
- Sete dias num seletor horizontal; tipografia do sistema, conteúdo rolável e adaptações para texto grande.
- Cabeçalho distingue praia escolhida de praia mais próxima **do catálogo**. Mostra distância em linha reta quando há GPS; não inventa duração de viagem nem junta Nazaré e Baleal num único local.
- Sem localização/autorização: permite escolher a praia; sem API: erro e retry; variável `null`: indisponível; dia sem janela adequada: diz explicitamente que não encontrou janela.
- O cartão apresenta a hora concreta da amostra mostrada. Não apresenta uma amostra horária como média diária.
- Comparação apenas com praias do catálogo até 25 km da praia selecionada; falhas parciais são visíveis.
- A tab bar continua a ser o TabView nativo; o aspeto pode variar com a versão do iOS, nomeadamente o estilo do iOS 26.

## Configuração de APIs

### Open-Meteo: configuração local completa, sem chave

- Marine: `https://marine-api.open-meteo.com/v1/marine`.
- Weather: `https://api.open-meteo.com/v1/forecast`.
- Ambos: `forecast_days=7`, `timezone=Europe/Lisbon`, `timeformat=unixtime`.
- Marine: altura/período/direção de onda e swell, temperatura da superfície do mar, `cell_selection=sea`.
- Weather: temperatura do ar, vento/direção/rajadas, UV, dia/noite, pôr do sol; `wind_speed_unit=kmh`.
- Cache apenas em memória. Atualização manual força novo pedido. Ao regressar à app e durante a utilização, previsões com mais de 15 minutos são atualizadas; janelas que já começaram são descartadas. Erros não são substituídos por dados de demonstração.
- Fontes e licença visíveis na Home e no painel Data & methodology. Rever o plano Open-Meteo antes de distribuição comercial.

Documentação: [Marine](https://open-meteo.com/en/docs/marine-weather-api), [Weather](https://open-meteo.com/en/docs), [termos](https://open-meteo.com/en/terms).

### Gemini: integração local preparada; ativação remota por confirmar

Projeto existente: `surfly-1a083`, app iOS `com.surfly`. Mantém o `GoogleService-Info.plist` existente. SDK: FirebaseAILogic 13.1.1. Modelo configurado: `gemini-3.5-flash-lite`, constante em `SurfAdvisorService` (confirmado na documentação consultada em 2026-11-02).

Passos concretos na [consola do projeto](https://console.firebase.google.com/project/surfly-1a083/overview):

1. Em AI Logic, iniciar configuração e selecionar Gemini Developer API. O fluxo ativa as APIs necessárias e gere a chave Gemini no serviço; não copiar a chave para Swift/plist.
2. Verificar o plano/quota já existente. Esta implementação não exige mudar para Blaze nem autoriza faturação nova.
3. Em App Check, registar `com.surfly` com DeviceCheck para dispositivo/Release. A chave de autenticação Apple/Team ID pertence ao titular da conta e não deve entrar no Git.
4. No simulador, correr a app e registar o token Debug emitido na consola Xcode em App Check > Manage debug tokens. Não commitar esse token.
5. Confirmar chamadas Gemini válidas antes de ativar enforcement de App Check. Não alterar enforcement do Firebase Auth como efeito colateral.

Estado: a consola foi aberta no navegador ligado e redirecionou para o início de sessão Google; não havia sessão autenticada. Não foi ativado nenhum serviço remoto. A conclusão depende de acesso à conta e, para DeviceCheck, às credenciais Apple. O advisor mostra erro e sugestão local identificada se o serviço estiver desativado, a quota se esgotar, a rede falhar ou a resposta não passar a validação.

A IA recebe nome da praia e parâmetros das janelas candidatas, sem GPS do utilizador, email, notas ou calendário. Só devolve IDs de horários fornecidos e a lista de equipamento permitida para a janela. Não há texto livre nem números gerados pela IA na UI. A comparação de praias é calculada localmente; a IA recebe o resultado verificado, não decide uma praia arbitrária.

Referências: [setup Firebase AI Logic](https://firebase.google.com/docs/ai-logic/get-started), [JSON estruturado](https://firebase.google.com/docs/ai-logic/generate-structured-output), [modelos](https://firebase.google.com/docs/ai-logic/models), [DeviceCheck](https://firebase.google.com/docs/app-check/ios/devicecheck-provider).

### CoreLocation / EventKit

Permissões declaradas no Info.plist gerado pelo Xcode, em ambas as configurações. CoreLocation pede acesso em utilização; a app aceita seleção manual. EventKit pede **write-only** apenas quando a pessoa toca em Save to Calendar. O modal grava no calendário predefinido real, com coordenadas, notas, previsão correspondente e alarme configurável. Não apresenta um calendário iCloud fictício nem lê eventos existentes. A futura tab Schedule poderá precisar de acesso completo, fora deste âmbito.

Os horários iniciais do formulário são valores editáveis de planeamento; quando não existe janela recomendada, não são apresentados como recomendação meteorológica. Se o horário escolhido não estiver coberto pela previsão recente, as notas dizem que a previsão/checklist não está disponível.

## Proveniência das praias

Coordenadas copiadas das fichas públicas ABAAE/Bandeira Azul (pontos de referência da praia; não localização do telefone, boias ou pontos de rebentação):

| Praia | Latitude | Longitude | Fonte |
| --- | --- | --- | --- |
| Baleal Norte | 39.373654 | -9.338815 | [ABAAE](https://bandeiraazul.abaae.pt/local-galardoado/baleal-norte/) |
| Baleal Sul | 39.370671 | -9.338611 | [ABAAE](https://bandeiraazul.abaae.pt/local-galardoado/baleal-sul/) |
| Cova da Alfarroba | 39.360483 | -9.364042 | [ABAAE](https://bandeiraazul.abaae.pt/local-galardoado/cova-da-alfarroba/) |
| Medão-Supertubos | 39.345665 | -9.36355 | [ABAAE](https://bandeiraazul.abaae.pt/local-galardoado/medao-supertubos/) |
| Nazaré | 39.599023 | -9.070031 | [ABAAE](https://bandeiraazul.abaae.pt/local-galardoado/nazare/) |

Orientações para o mar são aproximações locais de configuração (315°, 240°, 330°, 230°, 270°), não medições nem dados fornecidos pelo Open-Meteo. Devem ser revistas com conhecimento local antes de usar o índice como apoio operacional. A grelha do modelo pode ser igual em praias próximas; o painel de fontes apresenta a coordenada marinha devolvida pela API. Não se simula resolução local inexistente.

## Índice experimental v1 e recomendações

O relatório pede uma percentagem mas não fornece uma fórmula validada. A implementação distingue explicitamente um índice de produto de uma medição ou probabilidade de segurança.

- Ondas: abaixo de 0,3 m, 35 pontos (pouca onda); 0,3–0,9 m, 100; acima de 0,9 m, subtrai 100 por metro adicional até zero.
- Vento: 100 pontos até 5 km/h; subtrai 4 por km/h adicional até zero.
- Período: 100 pontos até 9 s; subtrai 12 por segundo adicional até zero.
- Soma ponderada: 60% ondas + 25% vento + 15% período. Vento onshore acima de 10 km/h subtrai 10 pontos.
- Limite de 25 pontos se ondas >1,5 m, vento >25 km/h, rajadas >35 km/h ou ondas >1 m com período >12 s.
- Sem altura/período/vento/direção/rajadas: sem índice. Temperatura ausente não é substituída por temperatura do ar.
- Janela: três amostras consecutivas, cobrindo duas horas futuras e diurnas, terminando antes do pôr do sol, todas com índice >=60. Ordena pelo pior índice da janela; empate favorece a mais cedo.
- Alternativa próxima: melhoria >=10 pontos sobre a praia atual nos **mesmos timestamps** e janela favorável completa.
- Fato: sugestões condicionais a temperaturas do ar e água completas; água <14°C ou ar <10°C => 5/4 mm e botas; água <18°C => 4/3 mm; restante => 3/2 mm. São regras orientativas de equipamento, a confirmar com instrutor. Sem temperaturas: pedir conselho ao instrutor. Prancha sem tamanho fixo; protetor recomendado se UV observado no modelo >=3.

Estes limiares são decisões de implementação transparentes, não um modelo validado por instrutores. Não modelam marés, correntes, fundos, bandeiras, vigilância ou perigos locais.

## Validação e execução

Verificações executadas em 2026-11-02:

- `git diff --check`: passou.
- Sintaxe Python do script de integração: passou.
- `scripts/verify_live_forecast.py`: passou nos dez pedidos HTTPS (cinco praias x duas APIs), às 20:07 UTC/Lisboa. Cada praia recebeu 168 horas coincidentes, unidades esperadas, sete pores do sol e 168 temperaturas da água disponíveis. Evidência local: `tmp/forecast-verification/verification.json` e payloads originais.
- O teste confirmou grelha marinha partilhada pelas quatro praias de Peniche: 39.375, -9.374985. Nazaré: 39.708336, -9.124985. A aplicação conserva estas coordenadas devolvidas pela API e explica a resolução no painel de fontes.

Ambiente de desenvolvimento desta alteração: Windows, sem Xcode, SDK iOS ou compilador Swift. Não é possível afirmar build, testes XCTest, simulador ou comparação visual iOS aprovados neste ambiente.

Em macOS com Xcode 26.2+:

```sh
xcodebuild -resolvePackageDependencies -project surfly.xcodeproj -scheme surfly
xcodebuild -list -project surfly.xcodeproj
xcodebuild -showdestinations -project surfly.xcodeproj -scheme surfly
# Substituir pelo UUID de um simulador iOS instalado:
xcodebuild test -project surfly.xcodeproj -scheme surfly -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -only-testing:surflyTests
```

Os testes novos cobrem ausência de dados, ondas/rajadas exigentes, noite/pôr do sol, intervalos passados e com lacunas, unidades erradas, junção por hora, respostas AI inválidas e fronteiras de dia em Lisboa. Os únicos números sintéticos estão no target XCTest, nunca nas vistas/preview.

Verificação independente das APIs, sem conta/chave:

```sh
python scripts/verify_live_forecast.py
```

Checklist manual em iOS: GPS autorizado/negado, escolha manual, todos os dias, ausência de rede, pull-to-refresh, troca rápida de praia/dia, retorno após meia-noite, erro/quota Gemini, Dynamic Type, ecrã pequeno/iPad, login falhado, calendário negado, cancelamento e confirmação real de gravação. Não foram executados nesta máquina.
