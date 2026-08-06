import Foundation

/// How small each kind of section is allowed to get.
///
/// Injected rather than looked up, so the layout engine never learns that sections — let
/// alone views — exist. In the app this is backed by `SectionDescriptor.minimumSize`; in
/// tests it is a literal table.
public struct MinimumSizePolicy: Sendable {
    private let lookup: @Sendable (SectionID) -> LayoutSize

    public init(_ lookup: @escaping @Sendable (SectionID) -> LayoutSize) {
        self.lookup = lookup
    }

    public func callAsFunction(_ sectionID: SectionID) -> LayoutSize {
        lookup(sectionID)
    }

    /// Every section gets `LayoutSize.default`.
    public static let uniform = MinimumSizePolicy { _ in .default }

    public static func constant(_ size: LayoutSize) -> MinimumSizePolicy {
        MinimumSizePolicy { _ in size }
    }

    public static func table(
        _ table: [SectionID: LayoutSize],
        fallback: LayoutSize = .default
    ) -> MinimumSizePolicy {
        MinimumSizePolicy { table[$0] ?? fallback }
    }
}
