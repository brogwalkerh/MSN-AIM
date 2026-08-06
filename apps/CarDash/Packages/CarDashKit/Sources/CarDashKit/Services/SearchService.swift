import MapKit
import Observation
import CarDashCore
import os

/// Destination search: as-you-type suggestions, then resolution to a real place.
@MainActor
@Observable
public final class SearchService {
    public struct Suggestion: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
    }

    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions = []
                completer.cancel()
            } else {
                completer.queryFragment = query
            }
        }
    }

    public private(set) var suggestions: [Suggestion] = []
    public private(set) var isSearching = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let delegate = CompleterDelegate()
    @ObservationIgnored private var completions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "search")

    public init() {
        // Addresses and points of interest only. Without this the list fills with
        // "query" suggestions — half-typed search terms — which are useless as
        // destinations and push the real results off a small screen.
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = delegate
        delegate.onResults = { [weak self] results in
            self?.apply(results)
        }
    }

    /// Biases results towards the car rather than wherever the map happens to be.
    public func setRegion(around coordinate: Coordinate, spanMetres: Double = 50_000) {
        completer.region = MKCoordinateRegion(
            center: coordinate.clCoordinate,
            latitudinalMeters: spanMetres,
            longitudinalMeters: spanMetres
        )
    }

    /// Turns a suggestion into a place with coordinates.
    public func resolve(_ suggestion: Suggestion) async -> MKMapItem? {
        guard let completion = completions.first(where: { key(for: $0) == suggestion.id }) else {
            return nil
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let response = try await MKLocalSearch(request: .init(completion: completion)).start()
            return response.mapItems.first
        } catch {
            Self.log.error("could not resolve \(suggestion.title): \(error)")
            return nil
        }
    }

    public func clear() {
        query = ""
        suggestions = []
        completions = []
    }

    private func apply(_ results: [MKLocalSearchCompletion]) {
        completions = results
        suggestions = results.prefix(8).map {
            Suggestion(id: key(for: $0), title: $0.title, subtitle: $0.subtitle)
        }
    }

    private func key(for completion: MKLocalSearchCompletion) -> String {
        "\(completion.title)|\(completion.subtitle)"
    }
}

/// `MKLocalSearchCompleterDelegate` is not main-actor-annotated, so the conformance
/// lives on a separate object. The callbacks do arrive on the main thread.
private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    var onResults: (@MainActor ([MKLocalSearchCompletion]) -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        MainActor.assumeIsolated { onResults?(results) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        // A failed completion is usually just a fast typist cancelling the previous
        // request. Clearing is the right response; logging every one is noise.
        MainActor.assumeIsolated { onResults?([]) }
    }
}
