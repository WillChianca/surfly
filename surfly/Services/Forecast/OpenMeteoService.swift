import Foundation

enum ForecastError: LocalizedError {
    case server(Int), invalidResponse, noData, inlandLocation
    var errorDescription: String? {
        switch self {
        case .server(429): "The forecast provider is busy. Please try again shortly."
        case .server: "The forecast provider could not complete this request."
        case .invalidResponse: "The forecast response could not be read."
        case .noData: "No forecast data is available for this beach."
        case .inlandLocation: "No nearby marine grid is available. Choose a coastal beach or move the pin closer to the sea."
        }
    }
}

/// Both APIs use Unix timestamps: joining by index or parsing local wall time breaks at DST.
@MainActor
final class OpenMeteoService {
    private let session: URLSession
    private var cache: [String: BeachForecast] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func forecast(for beach: SurfBeach, refresh: Bool = false) async throws -> BeachForecast {
        if !refresh, let cached = cache[beach.id], Date().timeIntervalSince(cached.fetchedAt) < 900 {
            return cached
        }
        async let marine: OpenMeteoResponse = fetch(url: Self.url(for: beach, marine: true))
        async let weather: OpenMeteoResponse = fetch(url: Self.url(for: beach, marine: false))
        let result = try await Self.merge(marine: marine, weather: weather, beach: beach)
        cache[beach.id] = result
        return result
    }

    static func url(for beach: SurfBeach, marine: Bool) -> URL {
        var url = URLComponents(string: marine
            ? "https://marine-api.open-meteo.com/v1/marine"
            : "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(beach.latitude)),
            .init(name: "longitude", value: String(beach.longitude)),
            .init(name: "forecast_days", value: "7"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "hourly", value: marine
                ? "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,sea_surface_temperature"
                : "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,is_day")
        ]
        if marine {
            url.queryItems?.append(.init(name: "cell_selection", value: "sea"))
        } else {
            url.queryItems?.append(.init(name: "wind_speed_unit", value: "kmh"))
            url.queryItems?.append(.init(name: "daily", value: "sunset"))
        }
        return url.url!
    }

    private func fetch(url: URL) async throws -> OpenMeteoResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ForecastError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ForecastError.server(http.statusCode) }
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    static func merge(marine: OpenMeteoResponse, weather: OpenMeteoResponse,
                      beach: SurfBeach, fetchedAt: Date = Date()) throws -> BeachForecast {
        guard let marineTimes = marine.hourly["time"], let weatherTimes = weather.hourly["time"],
              !marineTimes.isEmpty else { throw ForecastError.noData }
        guard marine.hourly_units["wave_height"] == "m",
              marine.hourly_units["wave_period"] == "s",
              weather.hourly_units["wind_speed_10m"] == "km/h",
              weather.hourly_units["wind_direction_10m"] == "°",
              weather.hourly_units["wind_gusts_10m"] == "km/h" else { throw ForecastError.invalidResponse }
        var weatherIndex: [Double: Int] = [:]
        for (index, time) in weatherTimes.enumerated() {
            if let time { weatherIndex[time] = index }
        }
        func value(_ response: OpenMeteoResponse, _ key: String, _ index: Int?,
                   unit: String? = nil, range: ClosedRange<Double>? = nil) -> Double? {
            guard let index, let values = response.hourly[key], values.indices.contains(index),
                  let number = values[index], number.isFinite else { return nil }
            if let unit, response.hourly_units[key] != unit { return nil }
            if let range, !range.contains(number) { return nil }
            return number
        }
        let hours = marineTimes.enumerated().compactMap { index, timestamp -> ForecastHour? in
            guard let timestamp, timestamp.isFinite else { return nil }
            let wi = weatherIndex[timestamp]
            return ForecastHour(
                time: Date(timeIntervalSince1970: timestamp),
                waveHeight: value(marine, "wave_height", index, unit: "m", range: 0...40),
                wavePeriod: value(marine, "wave_period", index, unit: "s", range: 0...40),
                waveDirection: value(marine, "wave_direction", index, unit: "°", range: 0...360),
                swellHeight: value(marine, "swell_wave_height", index, unit: "m", range: 0...40),
                swellPeriod: value(marine, "swell_wave_period", index, unit: "s", range: 0...40),
                swellDirection: value(marine, "swell_wave_direction", index, unit: "°", range: 0...360),
                waterTemperature: value(marine, "sea_surface_temperature", index, unit: "°C", range: -5...45),
                airTemperature: value(weather, "temperature_2m", wi, unit: "°C", range: -60...60),
                windSpeed: value(weather, "wind_speed_10m", wi, unit: "km/h", range: 0...400),
                windDirection: value(weather, "wind_direction_10m", wi, unit: "°", range: 0...360),
                windGusts: value(weather, "wind_gusts_10m", wi, unit: "km/h", range: 0...500),
                uvIndex: value(weather, "uv_index", wi, range: 0...30),
                isDay: value(weather, "is_day", wi) == 1)
        }.sorted { $0.time < $1.time }
        guard !hours.isEmpty else { throw ForecastError.noData }
        let grid = SurfBeach(id: "grid", name: "", region: "", latitude: marine.latitude,
                             longitude: marine.longitude, seawardBearing: nil)
        guard grid.location.distance(from: beach.location) <= 50_000 else { throw ForecastError.inlandLocation }
        var resolvedBeach = beach
        resolvedBeach.timeZoneIdentifier = weather.timezone ?? beach.timeZone.identifier
        return BeachForecast(beach: resolvedBeach, hours: hours,
                             sunsets: (weather.daily?["sunset"] ?? []).compactMap { $0.map { Date(timeIntervalSince1970: $0) } },
                             fetchedAt: fetchedAt, marineLatitude: marine.latitude, marineLongitude: marine.longitude,
                             timeZoneIdentifier: resolvedBeach.timeZone.identifier)
    }
}

struct OpenMeteoResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let hourly_units: [String: String]
    let hourly: [String: [Double?]]
    let daily: [String: [Double?]]?
    var timezone: String? = nil
}
