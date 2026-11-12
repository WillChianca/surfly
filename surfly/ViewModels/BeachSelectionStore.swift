import Foundation
import Combine
import CoreLocation

@MainActor
final class BeachSelectionStore: ObservableObject {
    @Published private(set) var selected: SurfBeach?
    @Published private(set) var recent: [SurfBeach] = []
    @Published private(set) var favourites: [SurfBeach] = []
    @Published var followsLocation = false
    @Published private(set) var findingNearest = false
    @Published private(set) var message: String?
    private var revision = UUID()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recent = Self.read([SurfBeach].self, key: "beaches.recent", defaults: defaults) ?? []
        favourites = Self.read([SurfBeach].self, key: "beaches.favourites", defaults: defaults) ?? []
        selected = Self.read(SurfBeach.self, key: "beaches.selected", defaults: defaults)
    }

    func select(_ beach: SurfBeach, fromLocation: Bool = false) {
        revision = UUID()
        selected = beach
        followsLocation = fromLocation
        findingNearest = false
        message = nil
        recent.removeAll { $0.id == beach.id }
        recent.insert(beach, at: 0)
        recent = Array(recent.prefix(20))
        save(beach, key: "beaches.selected")
        save(recent, key: "beaches.recent")
    }

    func toggleFavourite(_ beach: SurfBeach) {
        if favourites.contains(where: { $0.id == beach.id }) { favourites.removeAll { $0.id == beach.id } }
        else { favourites.append(beach) }
        save(favourites, key: "beaches.favourites")
    }

    func findNearest(to fix: CLLocation,
                     lookup: @MainActor (CLLocation) async throws -> [SurfBeach] = BeachDiscoveryService.nearby) async {
        let token = UUID()
        revision = token
        findingNearest = true
        message = nil
        defer { if revision == token { findingNearest = false } }
        let local = SurfBeach.catalogue.filter { $0.location.distance(from: fix) <= 25_000 }
        do {
            let found = try await lookup(fix)
            guard revision == token, followsLocation, !Task.isCancelled else { return }
            if let nearest = (found + local).min(by: { $0.location.distance(from: fix) < $1.location.distance(from: fix) }) {
                select(nearest, fromLocation: true)
            } else {
                message = "No beach was found within 25 km. Search by name or explore the map."
            }
        } catch {
            guard revision == token, followsLocation, !Task.isCancelled else { return }
            if let nearest = local.min(by: { $0.location.distance(from: fix) < $1.location.distance(from: fix) }) {
                select(nearest, fromLocation: true)
                message = "Online search failed. Showing the closest beach in the offline regional catalogue."
            } else { message = "Nearby beach search failed. Search again or choose a point on the map." }
        }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    private static func read<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
