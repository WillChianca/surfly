import XCTest
@testable import surfly

/// Synthetic edge cases for algorithms only. None of these values ship in the app or previews.
@MainActor
final class ForecastTests: XCTestCase {
    private let beach = SurfBeach.catalogue[0]
    private var start: Date { ISO8601DateFormatter().date(from: "2030-06-01T10:00:00Z")! }

    private func hour(offset: TimeInterval = 0, wave: Double? = 0.6, wind: Double? = 5,
                      gust: Double? = 8, period: Double? = 8, day: Bool = true) -> ForecastHour {
        ForecastHour(time: start.addingTimeInterval(offset), waveHeight: wave, wavePeriod: period,
                     waveDirection: nil, swellHeight: nil, swellPeriod: nil, swellDirection: nil,
                     waterTemperature: nil, airTemperature: nil, windSpeed: wind, windDirection: 90,
                     windGusts: gust, uvIndex: nil, isDay: day)
    }

    private func forecast(_ hours: [ForecastHour], sunset: TimeInterval = 9 * 3600) -> BeachForecast {
        BeachForecast(beach: beach, hours: hours, sunsets: [start.addingTimeInterval(sunset)],
                      fetchedAt: start, marineLatitude: beach.latitude, marineLongitude: beach.longitude)
    }

    func testMissingDataNeverBecomesZeroOrAValidScore() {
        XCTAssertNil(ForecastEngine.score(hour(wave: nil), beach: beach))
        XCTAssertNil(ForecastEngine.score(hour(wind: nil), beach: beach))
        XCTAssertNil(ForecastEngine.score(hour(gust: nil), beach: beach))
        XCTAssertNil(ForecastEngine.score(hour(period: nil), beach: beach))
    }

    func testLargeWavesAndGustsCannotBeOffsetByOtherwiseCalmConditions() throws {
        XCTAssertLessThanOrEqual(try XCTUnwrap(ForecastEngine.score(hour(wave: 2), beach: beach)), 25)
        XCTAssertLessThanOrEqual(try XCTUnwrap(ForecastEngine.score(hour(gust: 40), beach: beach)), 25)
    }

    func testFutureContinuousDaylightWindowIsRequired() {
        let valid = [hour(), hour(offset: 3600), hour(offset: 7200)]
        XCTAssertEqual(ForecastEngine.windows(in: forecast(valid), day: start, now: start).count, 1)
        XCTAssertTrue(ForecastEngine.windows(in: forecast(valid), day: start, now: start.addingTimeInterval(1)).isEmpty)
        let gap = [hour(), hour(offset: 3600), hour(offset: 10800)]
        XCTAssertTrue(ForecastEngine.windows(in: forecast(gap), day: start, now: start).isEmpty)
        let night = [hour(), hour(offset: 3600), hour(offset: 7200, day: false)]
        XCTAssertTrue(ForecastEngine.windows(in: forecast(night), day: start, now: start).isEmpty)
        XCTAssertTrue(ForecastEngine.windows(in: forecast(valid, sunset: 7000), day: start, now: start).isEmpty)
    }

    func testNoWindowWithMissingOrChallengingSample() {
        let incomplete = [hour(), hour(offset: 3600, wave: nil), hour(offset: 7200)]
        let demanding = [hour(), hour(offset: 3600, wave: 2), hour(offset: 7200)]
        XCTAssertTrue(ForecastEngine.windows(in: forecast(incomplete), day: start, now: start).isEmpty)
        XCTAssertTrue(ForecastEngine.windows(in: forecast(demanding), day: start, now: start).isEmpty)
    }

    func testUnknownTemperatureDoesNotInventWetsuitThickness() {
        let gear = ForecastEngine.gear(for: [hour()])
        XCTAssertTrue(gear.contains(.askInstructor))
        XCTAssertFalse(gear.contains(.wetsuitWarm))
        XCTAssertFalse(gear.contains(.wetsuitMild))
        XCTAssertFalse(gear.contains(.wetsuitCold))
        XCTAssertFalse(gear.contains(.sunscreen)) // UV is absent, never silently replaced with a value.
    }

    func testWindAngleWrapsAcrossNorth() {
        XCTAssertEqual(ForecastEngine.angularDistance(359, 1), 2)
        XCTAssertEqual(ForecastEngine.angularDistance(0, 360), 0)
    }

    func testAIRejectsUnprovidedTimeAndEquipment() throws {
        let window = try XCTUnwrap(ForecastEngine.windows(
            in: forecast([hour(), hour(offset: 3600), hour(offset: 7200)]), day: start, now: start).first)
        XCTAssertThrowsError(try SurfAdvisorService.validate(
            AdvisorSelection(windowID: "invented-time", gearIDs: []), candidates: [window]))
        XCTAssertThrowsError(try SurfAdvisorService.validate(
            AdvisorSelection(windowID: window.id, gearIDs: ["invented-board-size"]), candidates: [window]))
        let gear = ForecastEngine.gear(for: window.hours).map(\.rawValue)
        let result = try SurfAdvisorService.validate(AdvisorSelection(windowID: window.id, gearIDs: gear), candidates: [window])
        XCTAssertEqual(result.window?.start, window.start)
        XCTAssertTrue(result.isAI)
    }

    func testMarineAndWeatherJoinByTimestampNotArrayIndex() throws {
        let time = start.timeIntervalSince1970
        let marine = OpenMeteoResponse(latitude: beach.latitude, longitude: beach.longitude,
                                      hourly_units: ["wave_height": "m", "wave_period": "s"],
                                      hourly: ["time": [time, time + 3600], "wave_height": [nil, 0.5], "wave_period": [8, 8]], daily: nil)
        let weather = OpenMeteoResponse(latitude: beach.latitude, longitude: beach.longitude,
                                       hourly_units: ["wind_speed_10m": "km/h", "wind_direction_10m": "°", "wind_gusts_10m": "km/h"],
                                       hourly: ["time": [time + 3600], "wind_speed_10m": [12], "wind_direction_10m": [90], "wind_gusts_10m": [15]], daily: nil)
        let result = try OpenMeteoService.merge(marine: marine, weather: weather, beach: beach, fetchedAt: start)
        XCTAssertNil(result.hours[0].waveHeight)
        XCTAssertNil(result.hours[0].windSpeed)
        XCTAssertEqual(result.hours[1].windSpeed, 12)
        XCTAssertNil(result.hours[1].waterTemperature)
        XCTAssertNil(ForecastEngine.score(result.hours[0], beach: beach))
    }

    func testUnitMismatchFailsInsteadOfMislabelingWind() {
        let response = OpenMeteoResponse(latitude: 0, longitude: 0, hourly_units: ["wind_speed_10m": "mp/h"],
                                        hourly: ["time": [start.timeIntervalSince1970]], daily: nil)
        XCTAssertThrowsError(try OpenMeteoService.merge(marine: response, weather: response, beach: beach))
    }

    func testRequestsUseSevenDaysMetricUnitsAndUnixTime() {
        for marine in [false, true] {
            let components = URLComponents(url: OpenMeteoService.url(for: beach, marine: marine), resolvingAgainstBaseURL: false)!
            let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(query["forecast_days"], "7")
            XCTAssertEqual(query["timeformat"], "unixtime")
            XCTAssertEqual(query["timezone"], "Europe/Lisbon")
            XCTAssertNil(query["apikey"])
        }
    }

    func testLisbonDayBoundariesUseBeachTimezone() {
        let instant = ISO8601DateFormatter().date(from: "2030-06-01T23:30:00Z")!
        XCTAssertEqual(ForecastClock.text(instant, format: "yyyy-MM-dd"), "2030-06-02")
    }
}
