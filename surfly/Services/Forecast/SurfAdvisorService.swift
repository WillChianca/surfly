import Foundation
import FirebaseAILogic

enum SurfAdvisorError: LocalizedError {
    case invalidResponse
    var errorDescription: String? { "The advisor returned a recommendation that could not be verified." }
}

/// Gemini selects IDs, never generates displayed measurements, percentages or times.
@MainActor
final class SurfAdvisorService {
    static let modelName = "gemini-3.5-flash-lite"

    func advise(beach: SurfBeach, windows: [SurfWindow], nearby: String?) async throws -> SurfAdvice {
        let candidates = Array(windows.prefix(6))
        guard !candidates.isEmpty else { return SurfAdvice(window: nil, gear: [], isAI: false) }
        let schema = Schema.object(properties: [
            "windowID": .enumeration(values: candidates.map(\.id)),
            "gearIDs": .array(items: .enumeration(values: GearItem.allCases.map(\.rawValue)))
        ])
        let model = FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: Self.modelName,
            generationConfig: GenerationConfig(responseMIMEType: "application/json", responseSchema: schema))
        let input = candidates.map { window in
            AdvisorCandidate(id: window.id, score: window.score,
                             hours: window.hours.map(AdvisorHour.init),
                             allowedGearIDs: ForecastEngine.gear(for: window.hours).map(\.rawValue))
        }
        let payload = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let prompt = """
        Help a beginner plan an instructor-led surf lesson at \(beach.name).
        Select the most suitable candidate from this real Open-Meteo forecast JSON.
        Consider wave height and period, wind and gusts, air/water temperature and UV.
        The score is an unvalidated planning heuristic, never a safety guarantee.
        Do not infer tides, currents, lifeguards, local breaking waves or missing values.
        Return a supplied windowID and exactly that candidate's allowedGearIDs.
        No free text, new measurements, dates, equipment sizes or invented values.
        Verified nearby comparison: \(nearby ?? "No verified better alternative available").
        Candidates: \(payload)
        """
        let response = try await model.generateContent(prompt)
        try Task.checkCancellation()
        guard let text = response.text, let data = text.data(using: .utf8) else { throw SurfAdvisorError.invalidResponse }
        let selection = try JSONDecoder().decode(AdvisorSelection.self, from: data)
        return try Self.validate(selection, candidates: candidates)
    }

    static func validate(_ selection: AdvisorSelection, candidates: [SurfWindow]) throws -> SurfAdvice {
        guard let window = candidates.first(where: { $0.id == selection.windowID }) else { throw SurfAdvisorError.invalidResponse }
        let allowed = ForecastEngine.gear(for: window.hours)
        guard selection.gearIDs.count == allowed.count,
              Set(selection.gearIDs) == Set(allowed.map(\.rawValue)) else { throw SurfAdvisorError.invalidResponse }
        return SurfAdvice(window: window, gear: allowed, isAI: true)
    }
}

struct AdvisorSelection: Decodable {
    let windowID: String
    let gearIDs: [String]
}

private struct AdvisorCandidate: Encodable {
    let id: String
    let score: Int
    let hours: [AdvisorHour]
    let allowedGearIDs: [String]
}

private struct AdvisorHour: Encodable {
    let unixTime: Double
    let waveMetres: Double?
    let periodSeconds: Double?
    let waveDirectionDegrees: Double?
    let swellMetres: Double?
    let swellPeriodSeconds: Double?
    let swellDirectionDegrees: Double?
    let windKmh: Double?
    let windDirectionDegrees: Double?
    let gustKmh: Double?
    let waterCelsius: Double?
    let airCelsius: Double?
    let uvIndex: Double?
    init(_ hour: ForecastHour) {
        unixTime = hour.time.timeIntervalSince1970
        waveMetres = hour.waveHeight
        periodSeconds = hour.wavePeriod
        waveDirectionDegrees = hour.waveDirection
        swellMetres = hour.swellHeight
        swellPeriodSeconds = hour.swellPeriod
        swellDirectionDegrees = hour.swellDirection
        windKmh = hour.windSpeed
        windDirectionDegrees = hour.windDirection
        gustKmh = hour.windGusts
        waterCelsius = hour.waterTemperature
        airCelsius = hour.airTemperature
        uvIndex = hour.uvIndex
    }
}
