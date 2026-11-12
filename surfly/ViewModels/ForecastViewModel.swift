import Foundation
import Combine
import CoreLocation

@MainActor
final class ForecastViewModel: ObservableObject {
    @Published var beach: SurfBeach?
    @Published var selectedDay = ForecastClock.calendar.startOfDay(for: Date())
    @Published private(set) var forecast: BeachForecast?
    @Published private(set) var nearby: [BeachForecast] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isComparing = false
    @Published private(set) var error: String?
    @Published private(set) var comparisonError: String?
    @Published private(set) var advice: SurfAdvice?
    @Published private(set) var isAdvising = false
    @Published private(set) var advisorError: String?
    @Published var refreshID = UUID()
    private let api = OpenMeteoService()
    private let advisor = SurfAdvisorService()
    private var requestID = UUID()
    private var adviceTask: Task<Void, Never>?
    private var adviceID = UUID()

    var timeZone: TimeZone { forecast?.timeZone ?? beach?.timeZone ?? .current }
    var calendar: Calendar { ForecastClock.calendar(in: timeZone) }

    var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var selectedHours: [ForecastHour] { forecast?.hours(on: selectedDay) ?? [] }
    var windows: [SurfWindow] {
        guard let forecast else { return [] }
        return ForecastEngine.windows(in: forecast, day: selectedDay)
    }
    var displayHour: ForecastHour? {
        if let hour = advice?.window?.hours.first { return hour }
        let now = Date()
        return selectedHours.first { $0.time >= now && $0.isDay }
            ?? selectedHours.first { $0.time >= now }
    }
    var score: Int? {
        guard let displayHour, let beach else { return nil }
        return ForecastEngine.score(displayHour, beach: beach)
    }
    var betterSpot: BeachForecast? {
        guard let primary = forecast else { return nil }
        return nearby.filter { candidate in
            guard let window = ForecastEngine.windows(in: candidate, day: selectedDay).first else { return false }
            // Compare the same timestamps, not each beach at a different time.
            let matched = primary.hours.filter { $0.time >= window.start && $0.time <= window.end }
            guard matched.count == window.hours.count,
                  matched.map(\.time) == window.hours.map(\.time) else { return false }
            let scores = matched.compactMap { ForecastEngine.score($0, beach: primary.beach) }
            guard scores.count == matched.count, let worst = scores.min() else { return false }
            return window.score >= worst + 10
        }.sorted {
            (ForecastEngine.windows(in: $0, day: selectedDay).first?.score ?? 0)
                > (ForecastEngine.windows(in: $1, day: selectedDay).first?.score ?? 0)
        }.first
    }

    func load(refresh: Bool = false) async {
        let token = UUID()
        requestID = token
        adviceID = UUID()
        adviceTask?.cancel()
        forecast = nil
        nearby = []
        advice = nil
        advisorError = nil
        error = nil
        comparisonError = nil
        isAdvising = false
        isComparing = false
        guard let beach else { isLoading = false; return }
        isLoading = true
        do {
            let loaded = try await api.forecast(for: beach, refresh: refresh)
            try Task.checkCancellation()
            guard requestID == token else { return }
            forecast = loaded
            if !days.contains(selectedDay), let first = days.first { selectedDay = first }
            isLoading = false
            isComparing = true
            let discovered: [SurfBeach]
            do { discovered = try await BeachDiscoveryService.nearby(beach.location) }
            catch {
                guard requestID == token, !Task.isCancelled else { return }
                discovered = []
                comparisonError = "Online nearby search is unavailable; checking the regional catalogue where available."
            }
            guard requestID == token, !Task.isCancelled else { return }
            var seen = Set<String>()
            let candidates = (discovered + SurfBeach.catalogue).filter {
                let key = BeachDiscoveryService.identifier(latitude: $0.latitude, longitude: $0.longitude)
                return seen.insert(key).inserted && $0.location.distance(from: beach.location) > 100 &&
                $0.id != beach.id && $0.location.distance(from: beach.location) <= 25_000
            }.sorted { $0.location.distance(from: beach.location) < $1.location.distance(from: beach.location) }.prefix(4)
            for candidate in candidates {
                do {
                    let other = try await api.forecast(for: candidate, refresh: refresh)
                    try Task.checkCancellation()
                    guard requestID == token else { return }
                    nearby.append(other)
                } catch {
                    guard requestID == token, !Task.isCancelled else { return }
                    comparisonError = "Some nearby forecasts could not be checked."
                }
            }
            guard requestID == token else { return }
            isComparing = false
            updateAdvice()
        } catch {
            guard requestID == token else { return }
            isLoading = false
            isComparing = false
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func updateAdvice() {
        adviceTask?.cancel()
        let token = UUID()
        adviceID = token
        advice = nil
        advisorError = nil
        isAdvising = false
        guard let beach, forecast?.beach.id == beach.id else { return }
        let options = windows
        let localWindow = options.first
        advice = SurfAdvice(window: localWindow, gear: localWindow.map { ForecastEngine.gear(for: $0.hours) } ?? [], isAI: false)
        guard !options.isEmpty, !isComparing, AppSettings.aiEnabled else { return }
        isAdvising = true
        let comparison = betterSpot.map { "\($0.beach.name) has a higher computed score in the same time window." }
        adviceTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.adviceID == token { self.isAdvising = false } }
            do {
                let result = try await self.advisor.advise(beach: beach, windows: options, nearby: comparison)
                guard !Task.isCancelled, self.adviceID == token else { return }
                self.advice = result
            } catch {
                guard !Task.isCancelled, self.adviceID == token else { return }
                self.advisorError = "AI advisor unavailable. Showing a forecast-based suggestion."
            }
        }
    }
}
