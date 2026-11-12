import SwiftUI
import MapKit
import Combine

@MainActor
final class MapForecastModel: ObservableObject {
    @Published private(set) var forecasts: [String: BeachForecast] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private let api = OpenMeteoService()

    func load(_ beach: SurfBeach) async {
        do {
            let value = try await api.forecast(for: beach)
            try Task.checkCancellation()
            forecasts[beach.id] = value
            errors[beach.id] = nil
        } catch {
            if !Task.isCancelled { errors[beach.id] = error.localizedDescription }
        }
    }
    func hour(for beach: SurfBeach) -> ForecastHour? {
        forecasts[beach.id]?.hours.first { $0.time >= Date() && $0.isDay }
    }
    func score(for beach: SurfBeach) -> Int? {
        guard let hour = hour(for: beach) else { return nil }
        return ForecastEngine.score(hour, beach: beach)
    }
}

struct ExploreBeachesView: View {
    @EnvironmentObject private var selection: BeachSelectionStore
    @EnvironmentObject private var location: BeachLocationService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var discovery = BeachDiscoveryService()
    @StateObject private var forecasts = MapForecastModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showSearch = false
    @State private var showPinName = false
    @State private var pinName = ""
    @State private var pendingPoint: CLLocationCoordinate2D?
    @AppStorage("distanceUnit") private var distanceUnit = "km"
    let onForecast: () -> Void

    private var pins: [SurfBeach] {
        var seen = Set<String>()
        return ([selection.selected].compactMap { $0 } + discovery.results + selection.favourites + selection.recent + SurfBeach.catalogue)
            .filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                SurflyPageHeader(eyebrow: "Explore nearby", title: "Find your wave")
                HStack(spacing: 10) {
                    Button { showSearch = true } label: {
                        Label("Search any beach…", systemImage: "magnifyingglass")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        selection.followsLocation = true
                        location.request()
                        position = .userLocation(fallback: .automatic)
                    } label: {
                        Group { if location.isLocating { ProgressView() } else { Image(systemName: "location") } }
                            .frame(width: 44, height: 44).background(SurflyTheme.warmSand, in: Circle())
                    }.accessibilityLabel("Find beaches near my location")
                }
                if let message = location.message ?? selection.message {
                    Text(message).font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
                if location.isApproximate { Text("Approximate location · distances are approximate").font(.caption2).foregroundStyle(SurflyTheme.mutedText) }
            }.padding(18)
            Map(position: $position) {
                UserAnnotation()
                ForEach(pins) { beach in
                    Annotation(beach.name, coordinate: beach.coordinate, anchor: .bottom) {
                        Button { selection.select(beach) } label: {
                            HStack(spacing: 8) {
                                VStack(spacing: 3) {
                                    Image(systemName: "water.waves")
                                    Text(forecasts.score(for: beach).map(String.init) ?? "—").font(.headline)
                                }
                                Text(beach.name).font(.caption.weight(.semibold)).lineLimit(2).frame(maxWidth: 112)
                            }
                            .foregroundStyle(selection.selected?.id == beach.id ? .white : SurflyTheme.darkSlate)
                            .padding(10)
                            .background(selection.selected?.id == beach.id ? SurflyTheme.forecastTeal : .white,
                                        in: RoundedRectangle(cornerRadius: 15))
                            .overlay(alignment: .bottom) {
                                Capsule().fill(pinColor(beach)).frame(height: 3).padding(.horizontal, 12)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                        }.buttonStyle(.plain).accessibilityLabel("\(beach.name), \(forecasts.score(for: beach).map { "index \($0)" } ?? "forecast not loaded")")
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([.beach])))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { context in visibleRegion = context.region }
            .overlay { Image(systemName: "plus").font(.title3).foregroundStyle(SurflyTheme.darkSlate).allowsHitTesting(false) }
            .overlay(alignment: .top) {
                HStack {
                    Button {
                        Task { await discovery.find("beaches", region: visibleRegion) }
                    } label: {
                        Label(discovery.isSearching ? "Searching…" : "Search this area", systemImage: "magnifyingglass")
                            .font(.caption.weight(.semibold)).padding(12).background(.regularMaterial, in: Capsule())
                    }.disabled(discovery.isSearching || visibleRegion == nil)
                    Button {
                        pendingPoint = visibleRegion?.center
                        pinName = ""
                        showPinName = pendingPoint != nil
                    } label: {
                        Label("Use centre", systemImage: "mappin.and.ellipse").font(.caption.weight(.semibold))
                            .padding(12).background(.regularMaterial, in: Capsule())
                    }.disabled(visibleRegion == nil)
                }.padding(10)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = discovery.error { Text(error).font(.caption).foregroundStyle(SurflyTheme.mutedText) }
                    if let beach = selection.selected { detail(beach) }
                    else {
                        Text("Choose a beach pin, search by name, or position the crosshair on a coastal beach and tap Use centre.")
                            .font(.subheadline).padding(8)
                    }
                }.padding(16).background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
            }
        }
        .background(SurflyTheme.background).tint(SurflyTheme.forecastTeal)
        .sheet(isPresented: $showSearch) {
            BeachSearchView(onSelect: { beach in selection.select(beach); centre(on: beach) })
        }
        .alert("Name this coastal point", isPresented: $showPinName) {
            TextField("Beach name", text: $pinName)
            Button("Cancel", role: .cancel) { pendingPoint = nil }
            Button("Select beach") {
                guard let point = pendingPoint, CLLocationCoordinate2DIsValid(point), !pinName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let beach = SurfBeach(id: BeachDiscoveryService.identifier(latitude: point.latitude, longitude: point.longitude),
                                      name: pinName.trimmingCharacters(in: .whitespacesAndNewlines), region: "Selected on map",
                                      latitude: point.latitude, longitude: point.longitude, seawardBearing: nil, source: "User-selected coastal point")
                selection.select(beach)
            }.disabled(pinName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("This is a point you choose, not a verified Apple Maps beach. Marine forecast coverage is checked separately.") }
        .task {
            if let beach = selection.selected { centre(on: beach) }
            else { position = .region(MKCoordinateRegion(center: SurfBeach.catalogue[0].coordinate, latitudinalMeters: 100_000, longitudinalMeters: 100_000)) }
        }
        .task(id: selection.selected?.id) {
            guard let beach = selection.selected else { return }
            centre(on: beach)
            await forecasts.load(beach)
        }
        .task(id: discovery.results.map(\.id).joined(separator: ",")) {
            for beach in discovery.results.prefix(6) {
                guard !Task.isCancelled else { return }
                await forecasts.load(beach)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let beach = selection.selected { Task { await forecasts.load(beach) } }
        }
    }

    private func centre(on beach: SurfBeach) {
        position = .region(MKCoordinateRegion(center: beach.coordinate, latitudinalMeters: 15_000, longitudinalMeters: 15_000))
    }
    private func pinColor(_ beach: SurfBeach) -> Color {
        guard let value = forecasts.score(for: beach) else { return .gray }
        return value >= 75 ? SurflyTheme.forecastTeal : value >= 60 ? .orange : SurflyTheme.accentCoralText
    }
    private func detail(_ beach: SurfBeach) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "water.waves").font(.title).foregroundStyle(SurflyTheme.forecastTeal)
                    .frame(width: 52, height: 52).background(SurflyTheme.warmSand, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR SELECTED BEACH").font(.caption2.weight(.bold)).foregroundStyle(SurflyTheme.forecastTeal)
                    Text(beach.name).font(.headline)
                    Text(beach.region).font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
                Spacer(minLength: 0)
                Button { selection.toggleFavourite(beach) } label: {
                    Image(systemName: selection.favourites.contains(where: { $0.id == beach.id }) ? "heart.fill" : "heart")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Toggle favourite beach")
            }
            if let fix = location.location {
                Text(AppSettings.distance(fix.distance(from: beach.location), unit: distanceUnit) + " · straight-line distance")
                    .font(.caption).foregroundStyle(SurflyTheme.mutedText)
            }
            if let hour = forecasts.hour(for: beach), let forecast = forecasts.forecasts[beach.id] {
                Text("\(forecasts.score(for: beach).map { "\($0)% planning index · " } ?? "")\(ForecastClock.text(hour.time, format: "EEE d MMM HH:mm", timeZone: forecast.timeZone)) · \(forecast.timeZoneIdentifier)")
                    .font(.caption).foregroundStyle(SurflyTheme.mutedText)
            } else if let error = forecasts.errors[beach.id] {
                Text(error).font(.caption).foregroundStyle(SurflyTheme.accentCoralText)
                Button("Retry forecast") { Task { await forecasts.load(beach) } }.font(.caption)
            } else if forecasts.forecasts[beach.id] != nil {
                Text("No upcoming daylight forecast sample is available.").font(.caption).foregroundStyle(SurflyTheme.mutedText)
            } else { ProgressView("Loading marine forecast…").font(.caption) }
            Button(action: onForecast) { Label("View beginner forecast", systemImage: "arrow.right") }
                .buttonStyle(ForecastPrimaryButton())
        }.foregroundStyle(SurflyTheme.darkSlate)
    }
}
