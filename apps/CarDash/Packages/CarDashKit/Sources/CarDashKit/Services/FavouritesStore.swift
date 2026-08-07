import Foundation
import Observation
import CarDashCore
import os

/// The saved favourites, shared by the Phone and Messages tiles.
///
/// One store rather than one per tile, because they are the same people — adding someone in
/// Phone should not leave Messages not knowing about them.
///
/// Stored in `UserDefaults` rather than in the layout document, and that is a privacy decision
/// rather than a convenience one. `SectionState` would have been the tidier home, but a layout
/// is a thing the user can export and share, and a shared dashboard arrangement has no business
/// carrying someone's phone numbers with it.
@MainActor
@Observable
public final class FavouritesStore {
    public private(set) var list: FavouritesList = FavouritesList()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "cardash.favourites"
    @ObservationIgnored private static let log = Logger(subsystem: "dev.cardash", category: "favourites")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public var entries: [Favourite] { list.entries }
    public var isEmpty: Bool { list.isEmpty }
    public var isFull: Bool { list.isFull }

    public func add(_ favourite: Favourite) {
        apply(list.adding(favourite))
    }

    /// What the contact picker hands back.
    public func add(contentsOf favourites: [Favourite]) {
        apply(list.adding(contentsOf: favourites))
    }

    public func remove(_ id: Favourite.ID) {
        apply(list.removing(id))
    }

    public func move(from source: Int, to destination: Int) {
        apply(list.moving(from: source, to: destination))
    }

    // MARK: - Persistence

    private func apply(_ new: FavouritesList) {
        guard new != list else { return }
        list = new
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            list = try JSONDecoder().decode(FavouritesList.self, from: data)
        } catch {
            // A list written by a build with a different shape is not worth losing the app
            // over; it means re-adding a handful of people.
            Self.log.error("could not read favourites: \(error)")
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(list), forKey: Self.key)
        } catch {
            Self.log.error("could not save favourites: \(error)")
        }
    }
}
