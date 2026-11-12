import MapKit
import Combine

@MainActor
final class BeachDiscoveryService: ObservableObject {
    @Published private(set) var results: [SurfBeach] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    private var search: MKLocalSearch?
    private var generation = UUID()

    func find(_ query: String, region: MKCoordinateRegion? = nil) async {
        search?.cancel()
        let token = UUID()
        generation = token
        error = nil
        results = []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { isSearching = false; return }
        isSearching = true
        defer { if generation == token { isSearching = false } }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.beach])
        if let region { request.region = region }
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard generation == token, !Task.isCancelled else { return }
            var seen = Set<String>()
            results = response.mapItems.compactMap { item in
                let coordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                let id = Self.identifier(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard seen.insert(id).inserted else { return nil }
                return SurfBeach(id: id, name: item.name ?? "Beach", region: [item.placemark.locality, item.placemark.country]
                    .compactMap { $0 }.joined(separator: ", "), latitude: coordinate.latitude, longitude: coordinate.longitude,
                    seawardBearing: nil, timeZoneIdentifier: item.timeZone?.identifier, source: "Apple Maps")
            }
            if results.isEmpty { error = "No beaches found here. Try a beach name and country, or choose a coastal point on the map." }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = "Beach search is unavailable. Check your connection or select a point on the map."
        }
    }

    static func identifier(latitude: Double, longitude: Double) -> String {
        String(format: "coordinate:%.5f:%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    static func nearby(_ location: CLLocation) async throws -> [SurfBeach] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "beaches"
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.beach])
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            let point = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(point) else { return nil }
            let beach = SurfBeach(id: identifier(latitude: point.latitude, longitude: point.longitude), name: item.name ?? "Beach",
                                 region: [item.placemark.locality, item.placemark.country].compactMap { $0 }.joined(separator: ", "),
                                 latitude: point.latitude, longitude: point.longitude, seawardBearing: nil,
                                 timeZoneIdentifier: item.timeZone?.identifier, source: "Apple Maps")
            return beach.location.distance(from: location) <= 25_000 ? beach : nil
        }
    }
}
