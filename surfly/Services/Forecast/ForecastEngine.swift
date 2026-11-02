import Foundation

/// Version 1 product heuristic, not a probability, a trained model or a beach safety assessment.
enum ForecastEngine {
    static func score(_ hour: ForecastHour, beach: SurfBeach) -> Int? {
        guard let wave = hour.waveHeight, let wind = hour.windSpeed,
              let direction = hour.windDirection, let period = hour.wavePeriod,
              let gust = hour.windGusts else { return nil }
        let wavePoints: Double = wave < 0.3 ? 35 : wave <= 0.9 ? 100 : max(0, 100 - (wave - 0.9) * 100)
        let windPoints = max(0, 100 - max(0, wind - 5) * 4)
        let periodPoints = max(0, 100 - max(0, period - 9) * 12)
        let onshore = angularDistance(direction, beach.seawardBearing) < 45
        var result = Int((wavePoints * 0.60 + windPoints * 0.25 + periodPoints * 0.15).rounded())
        if onshore && wind > 10 { result -= 10 }
        // Do not let a calm wind offset large/energetic waves or strong offshore wind.
        if wave > 1.5 || wind > 25 || gust > 35 || (wave > 1 && period > 12) { result = min(result, 25) }
        return min(100, max(0, result))
    }

    static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    static func windDescription(_ hour: ForecastHour, beach: SurfBeach) -> String {
        guard let direction = hour.windDirection, let speed = hour.windSpeed else { return "Unavailable" }
        if speed < 5 { return "Light wind" }
        let difference = angularDistance(direction, beach.seawardBearing)
        return difference < 45 ? "Onshore" : difference > 135 ? "Offshore" : "Cross-shore"
    }

    static func waveDescription(_ height: Double?) -> String {
        guard let height else { return "Unavailable" }
        switch height {
        case ..<0.3: return "Very small"
        case ..<0.6: return "Knee high"
        case ..<1.0: return "Waist high"
        case ..<1.5: return "Chest high"
        default: return "Large waves"
        }
    }

    static func windows(in forecast: BeachForecast, day: Date, now: Date = Date()) -> [SurfWindow] {
        let hours = forecast.hours(on: day)
        guard hours.count >= 3 else { return [] }
        let sunset = forecast.sunsets.first { ForecastClock.calendar.isDate($0, inSameDayAs: day) }
        guard let sunset else { return [] }
        return (0..<(hours.count - 2)).compactMap { index -> SurfWindow? in
            let samples = Array(hours[index...(index + 2)])
            guard samples[0].time >= now, samples[2].time <= sunset,
                  samples.allSatisfy(\.isDay),
                  samples[1].time.timeIntervalSince(samples[0].time) == 3600,
                  samples[2].time.timeIntervalSince(samples[1].time) == 3600 else { return nil }
            let scores = samples.compactMap { score($0, beach: forecast.beach) }
            guard scores.count == 3, let minimum = scores.min(), minimum >= 60 else { return nil }
            return SurfWindow(start: samples[0].time, end: samples[2].time, score: minimum, hours: samples)
        }.sorted { $0.score == $1.score ? $0.start < $1.start : $0.score > $1.score }
    }

    static func gear(for hours: [ForecastHour]) -> [GearItem] {
        guard !hours.isEmpty else { return [] }
        let waters = hours.compactMap(\.waterTemperature)
        let air = hours.compactMap(\.airTemperature)
        var gear: [GearItem] = []
        if waters.count == hours.count, air.count == hours.count,
           let water = waters.min(), let airMinimum = air.min() {
            gear.append(water < 14 || airMinimum < 10 ? .wetsuitCold : water < 18 ? .wetsuitMild : .wetsuitWarm)
        } else {
            gear.append(.askInstructor)
        }
        gear.append(.softboard)
        if hours.compactMap(\.uvIndex).contains(where: { $0 >= 3 }) { gear.append(.sunscreen) }
        return gear
    }
}
