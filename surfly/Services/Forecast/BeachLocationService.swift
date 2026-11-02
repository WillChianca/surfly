import CoreLocation
import Combine
import Foundation

@MainActor
final class BeachLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var message: String?
    @Published private(set) var isLocating = false
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        message = nil
        isLocating = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locate()
        default: unavailable()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: locate()
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
        guard let fix = locations.last, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 5_000, abs(fix.timestamp.timeIntervalSinceNow) < 300 else {
            unavailable()
            return
        }
        timeout?.cancel()
        isLocating = false
        location = fix
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { unavailable() }

    private func unavailable() {
        timeout?.cancel()
        isLocating = false
        location = nil
        message = "Location unavailable. Choose a beach to see its forecast."
    }
}
