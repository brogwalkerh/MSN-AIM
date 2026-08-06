import UIKit

/// Small tactile confirmations.
///
/// Worth more here than in a typical app: the driver's eyes belong on the road, so
/// "that worked" needs a channel that is not visual.
@MainActor
public enum Haptics {
    /// A divider has run into the limit of how far it can move.
    public static func limit() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
    }

    /// A tile was added, removed or swapped.
    public static func edit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// An action was refused — a split that would not fit, for instance.
    public static func refused() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
