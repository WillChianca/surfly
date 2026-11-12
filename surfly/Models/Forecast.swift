import Foundation
import CoreLocation

struct SurfBeach: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    /// Approximate seaward bearing; local geography, never a forecast observation.
    let seawardBearing: Double?
    var timeZoneIdentifier: String? = nil
    var source: String = "ABAAE beach catalogue"

    var timeZone: TimeZone { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var coordinate: CLLocationCoordinate2D { location.coordinate }

    // Regional catalogue of beach reference points, not device positions or marine grid cells.
    // Sources and precision are documented in docs/FORECAST_HOME.md.
    static let catalogue: [SurfBeach] = [
        .init(id: "baleal-norte", name: "Baleal Norte", region: "Peniche", latitude: 39.373654, longitude: -9.338815, seawardBearing: 315, timeZoneIdentifier: "Europe/Lisbon"),
        .init(id: "baleal-sul", name: "Baleal Sul", region: "Peniche", latitude: 39.370671, longitude: -9.338611, seawardBearing: 240, timeZoneIdentifier: "Europe/Lisbon"),
        .init(id: "cova-alfarroba", name: "Cova da Alfarroba", region: "Peniche", latitude: 39.360483, longitude: -9.364042, seawardBearing: 330, timeZoneIdentifier: "Europe/Lisbon"),
        .init(id: "supertubos", name: "Supertubos", region: "Peniche", latitude: 39.345665, longitude: -9.36355, seawardBearing: 230, timeZoneIdentifier: "Europe/Lisbon"),
        .init(id: "nazare", name: "Praia da Nazaré", region: "Nazaré", latitude: 39.599023, longitude: -9.070031, seawardBearing: 270, timeZoneIdentifier: "Europe/Lisbon")
    ]
}

enum ForecastClock {
    static let timeZone = TimeZone(identifier: "Europe/Lisbon")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    static func text(_ date: Date, format: String, timeZone: TimeZone = ForecastClock.timeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct ForecastHour: Identifiable {
    var id: Date { time }
    let time: Date
    let waveHeight: Double?
    let wavePeriod: Double?
    let waveDirection: Double?
    let swellHeight: Double?
    let swellPeriod: Double?
    let swellDirection: Double?
    let waterTemperature: Double?
    let airTemperature: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let windGusts: Double?
    let uvIndex: Double?
    let isDay: Bool
}

struct BeachForecast {
    let beach: SurfBeach
    let hours: [ForecastHour]
    let sunsets: [Date]
    let fetchedAt: Date
    let marineLatitude: Double
    let marineLongitude: Double
    var timeZoneIdentifier: String = "Europe/Lisbon"
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }
    var calendar: Calendar { ForecastClock.calendar(in: timeZone) }

    func hours(on day: Date) -> [ForecastHour] {
        hours.filter { calendar.isDate($0.time, inSameDayAs: day) }
    }
}

struct SurfWindow: Identifiable {
    var id: String { String(Int(start.timeIntervalSince1970)) }
    let start: Date
    let end: Date
    let score: Int
    let hours: [ForecastHour]
    var timeZoneIdentifier: String = "Europe/Lisbon"
    var label: String {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return "\(ForecastClock.text(start, format: "HH:mm", timeZone: zone)) – \(ForecastClock.text(end, format: "HH:mm", timeZone: zone))"
    }
}

enum GearItem: String, Codable, CaseIterable, Identifiable {
    case wetsuitWarm, wetsuitMild, wetsuitCold, askInstructor, softboard, sunscreen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wetsuitWarm: "3/2 mm wetsuit"
        case .wetsuitMild: "4/3 mm wetsuit"
        case .wetsuitCold: "5/4 mm wetsuit + boots"
        case .askInstructor: "Ask your instructor about warmth"
        case .softboard: "Instructor-fitted softboard"
        case .sunscreen: "Water-resistant sunscreen"
        }
    }
}

struct SurfAdvice {
    let window: SurfWindow?
    let gear: [GearItem]
    let isAI: Bool
}
