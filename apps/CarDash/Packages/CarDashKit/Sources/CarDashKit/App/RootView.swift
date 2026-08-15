import SwiftUI
import CarDashCore

/// The app's root view, and the composition root.
///
/// The one place the real object graph is built. Everything below it receives what it
/// needs, so previews and tests can substitute stubs without any of it reaching for a
/// singleton.
public struct RootView: View {
    @State private var model: LayoutModel
    @State private var services: AppServices

    @MainActor
    public init() {
        let services = AppServices()
        // Falling back to an in-memory store means a phone that cannot write to
        // Application Support — full disk, restricted container — still runs, with
        // layouts that last until the app quits. Refusing to launch would be worse.
        let store: any LayoutStore = (try? FileLayoutStore()) ?? InMemoryLayoutStore()
        self.init(
            model: LayoutModel(store: store, policy: services.registry.minimumSizePolicy),
            services: services
        )
    }

    @MainActor
    public init(model: LayoutModel, services: AppServices) {
        _model = State(initialValue: model)
        _services = State(initialValue: services)
    }

    public var body: some View {
        DashboardView(model: model, services: services)
            // A .cardash file opened from Files, Mail or AirDrop arrives here. Without this
            // the app is launched by the tap and then simply shows the dashboard, which
            // looks like the file was ignored.
            .onOpenURL { url in
                guard url.isFileURL,
                      url.pathExtension.caseInsensitiveCompare(LayoutTransfer.fileExtension)
                        == .orderedSame
                else { return }

                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                do {
                    try model.importDocument(from: try Data(contentsOf: url))
                    Haptics.edit()
                } catch let error as LayoutTransfer.ImportError {
                    model.lastRefusal = error.userFacingMessage
                } catch {
                    model.lastRefusal = "That layout file couldn't be read."
                }
            }
    }
}

// MARK: - Previews

@MainActor
private func previewServices() -> AppServices {
    AppServices(weather: WeatherStore(provider: StubWeatherProvider()))
}

@MainActor
private func previewModel(
    tree: LayoutTree = LayoutPresets.navigationFocus,
    editing: Bool = false,
    services: AppServices
) -> LayoutModel {
    let document = LayoutDocument(name: "Preview", tree: tree, now: Date())
    let model = LayoutModel(
        store: InMemoryLayoutStore([document]),
        policy: services.registry.minimumSizePolicy
    )
    model.isEditing = editing
    return model
}

/// Canned weather so previews and the simulator show a populated tile without a network
/// call or a location fix.
private struct StubWeatherProvider: WeatherProviding {
    func snapshot(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        let now = Date()
        return WeatherSnapshot(
            coordinate: coordinate,
            current: CurrentConditions(
                time: now,
                temperature: 14.5,
                apparentTemperature: 13.0,
                condition: .partlyCloudy,
                windSpeed: 3.4,
                isDaylight: true
            ),
            hourly: (1...6).map { hour in
                HourForecast(
                    time: now.addingTimeInterval(Double(hour) * 3600),
                    temperature: 14.5 + Double(hour) * 0.4,
                    precipitationProbability: Double(hour) / 20,
                    condition: hour > 3 ? .rain : .partlyCloudy
                )
            },
            fetchedAt: now,
            attribution: .openMeteo
        )
    }
}

#Preview("Dashboard", traits: .landscapeLeft) {
    let services = previewServices()
    RootView(model: previewModel(services: services), services: services)
}

#Preview("Rearranging", traits: .landscapeLeft) {
    let services = previewServices()
    RootView(model: previewModel(editing: true, services: services), services: services)
}

#Preview("Four up", traits: .landscapeLeft) {
    let services = previewServices()
    RootView(model: previewModel(tree: LayoutPresets.quad, services: services), services: services)
}

#Preview("Portrait (adapted)") {
    let services = previewServices()
    RootView(model: previewModel(tree: LayoutPresets.quad, services: services), services: services)
}
