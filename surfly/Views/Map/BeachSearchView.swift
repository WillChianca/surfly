import SwiftUI
import CoreLocation

struct BeachSearchView: View {
    @EnvironmentObject private var selection: BeachSelectionStore
    @EnvironmentObject private var location: BeachLocationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = BeachDiscoveryService()
    @State private var query = ""
    @AppStorage("distanceUnit") private var distanceUnit = "km"
    var onSelect: ((SurfBeach) -> Void)? = nil
    var onExploreMap: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                if onSelect == nil {
                    Button {
                        selection.followsLocation = true
                        location.request()
                        dismiss()
                    } label: { Label("Find a beach near me", systemImage: "location") }
                }
                if let onExploreMap {
                    Button { dismiss(); onExploreMap() } label: { Label("Choose a coastal point on the map", systemImage: "map") }
                }
                if !query.isEmpty {
                    Section("Apple Maps results") {
                        if search.isSearching { ProgressView("Searching beaches…") }
                        if let error = search.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                        beachRows(search.results)
                    }
                } else {
                    if !selection.favourites.isEmpty { Section("Favourites") { beachRows(selection.favourites) } }
                    if !selection.recent.isEmpty { Section("Recently viewed") { beachRows(selection.recent) } }
                    Section("Discover the Portuguese west coast") { beachRows(SurfBeach.catalogue) }
                    Text("Search a beach name and country anywhere in the world. Results depend on Apple Maps coverage; coastal points can also be selected on the map.")
                        .font(.caption).foregroundStyle(SurflyTheme.mutedText)
                }
            }
            .searchable(text: $query, prompt: "Beach name, city or country")
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                await search.find(query)
            }
            .navigationTitle("Find your beach")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(SurflyTheme.forecastTeal)
    }

    @ViewBuilder private func beachRows(_ beaches: [SurfBeach]) -> some View {
        ForEach(beaches) { beach in
            Button {
                if let onSelect { onSelect(beach) } else { selection.select(beach) }
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "water.waves").foregroundStyle(SurflyTheme.forecastTeal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(beach.name).font(.subheadline.weight(.semibold)).foregroundStyle(SurflyTheme.darkSlate)
                        Text(beach.region).font(.caption).foregroundStyle(SurflyTheme.mutedText)
                        if let fix = location.location {
                            Text(AppSettings.distance(fix.distance(from: beach.location), unit: distanceUnit) + " · straight line")
                                .font(.caption2).foregroundStyle(SurflyTheme.mutedText)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }.padding(.vertical, 4)
            }
        }
    }
}
