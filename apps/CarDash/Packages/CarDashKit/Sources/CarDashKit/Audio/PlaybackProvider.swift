import Foundation
import CarDashCore

/// One music source.
///
/// Providers report through a callback rather than an `AsyncStream` because everything
/// here is already main-actor bound and the events must be applied in order; a stream
/// would add a scheduling hop and a chance to reorder for no benefit.
@MainActor
public protocol PlaybackProvider: AnyObject {
    var id: ProviderID { get }

    /// False when the source cannot be used at all right now — Spotify not installed,
    /// media library access refused, no files imported. The picker greys these out with
    /// `unavailableReason` rather than letting the user select something inert.
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }

    /// Called by the coordinator; the provider reports state changes back through it.
    func attach(_ sink: @escaping @MainActor (ProviderEvent) -> Void)

    func perform(_ intent: PlaybackIntent)

    /// Called when another provider takes over, so this one can release what it holds.
    func relinquish()
}

extension PlaybackProvider {
    public var unavailableReason: String? { nil }
    public func relinquish() {}
}
