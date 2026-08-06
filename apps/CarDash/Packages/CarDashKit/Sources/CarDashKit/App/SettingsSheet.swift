import SwiftUI
import CarDashCore

struct SettingsSheet: View {
    let services: AppServices

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: Binding(
                        get: { services.unitSystem },
                        set: { services.unitSystem = $0 }
                    )) {
                        Text("Metric (km/h)").tag(UnitSystem.metric)
                        Text("Imperial (mph)").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Appearance", selection: Binding(
                        get: { services.theme.mode },
                        set: { services.theme.mode = $0 }
                    )) {
                        ForEach(ThemeController.Mode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } footer: {
                    Text("Automatic follows sunrise and sunset where you are, calculated on device — it keeps working with no signal.")
                }

                Section("Location") {
                    LabeledContent("Status", value: statusText)
                    if let coordinate = services.location.coordinate {
                        LabeledContent("Position") {
                            Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                                .monospacedDigit()
                        }
                    }
                    LabeledContent("Trip") {
                        Text(UnitFormatting.distance(
                            meters: services.location.trip.distance,
                            system: services.unitSystem
                        ))
                    }
                    Button("Reset trip", role: .destructive) {
                        services.location.resetTrip()
                    }
                }

                // Stated plainly and up front, rather than left to be discovered while
                // driving. These are OS limits, not things left undone.
                Section("What iOS does not allow") {
                    limitation("No app can display another app's screen, so each tile is CarDash's own interface talking to that service.")
                    limitation("Messages cannot be read aloud, and replies always need a tap to send.")
                    limitation("YouTube audio stops when you leave the app or lock the screen.")
                    limitation("When the phone locks, this screen is gone — audio and navigation keep running.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func limitation(_ text: String) -> some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: "info.circle")
        }
    }

    private var statusText: String {
        switch services.location.status {
        case .idle: return "Not started"
        case .running: return services.location.coordinate == nil ? "Searching…" : "Active"
        case .denied: return "Denied — enable in Settings"
        case .restricted: return "Restricted"
        case .unavailable: return "Unavailable"
        }
    }
}
