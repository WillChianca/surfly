import CoreLocation
import Combine
import Foundation

@MainActor
final class BeachLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var message: String?
    @Published private(set) var isLocating = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isApproximate = false
    @Published private(set) var fixID = UUID()
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    func request() {
        timeout?.cancel()
        manager.stopUpdatingLocation()
        location = nil
        fixID = UUID()
        message = nil
        isLocating = true
        authorization = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locate()
        default: unavailable()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: if isLocating { locate() }
        case .denied, .restricted: unavailable()
        default: break
        }
    }

    private func locate() {
        manager.requestLocation()
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.isLocating else { return }
            self.manager.stopUpdatingLocation()
            self.unavailable()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocating, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }
        guard let fix = locations.last, Self.isUsable(fix) else {
            unavailable()
            return
        }
        timeout?.cancel()
        isLocating = false
        location = fix
        fixID = UUID()
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy || fix.horizontalAccuracy > 1000
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isLocating else { return }
        if (error as? CLError)?.code == .locationUnknown { return } // Allow the bounded request to recover.
        unavailable()
    }

    static func isUsable(_ fix: CLLocation, now: Date = Date()) -> Bool {
        CLLocationCoordinate2DIsValid(fix.coordinate) && fix.horizontalAccuracy >= 0
            && fix.horizontalAccuracy <= 5_000 && abs(fix.timestamp.timeIntervalSince(now)) < 300
    }

    func recheckPermission() {
        authorization = manager.authorizationStatus
        if authorization == .denied || authorization == .restricted { unavailable() }
        else if let location, !Self.isUsable(location) { self.location = nil }
    }

    private func unavailable() {
        timeout?.cancel()
        manager.stopUpdatingLocation()
        isLocating = false
        location = nil
        fixID = UUID()
        message = "Location unavailable. Choose a beach to see its forecast."
    }
}
