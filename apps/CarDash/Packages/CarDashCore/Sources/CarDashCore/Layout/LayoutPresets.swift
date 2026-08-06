import Foundation

/// The layouts the app ships with.
///
/// Expressed as Swift rather than parsed from a bundled resource so that they are
/// compiled, refactored with the rest of the code, and — most usefully — checked by a
/// test that every preset actually fits on the screens the app runs on. A preset that
/// silently violates a minimum size is the kind of thing that otherwise only shows up on
/// the user's phone.
public enum LayoutPresets {
    public struct Preset: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let systemImage: String
        public let summary: String
        /// A closure rather than a stored tree: every instantiation needs fresh pane and
        /// divider identifiers, or two dashboards created from the same preset would
        /// share identity.
        public let makeTree: @Sendable () -> LayoutTree

        public func tree() -> LayoutTree { makeTree() }

        public func document(named name: String? = nil, now: Date) -> LayoutDocument {
            LayoutDocument(name: name ?? self.name, tree: makeTree(), now: now)
        }
    }

    public static let all: [Preset] = [
        Preset(
            id: "navigationFocus",
            name: "Navigation",
            systemImage: "map.fill",
            summary: "Map takes two thirds, music and gauges stacked beside it.",
            makeTree: { navigationFocus }
        ),
        Preset(
            id: "mediaFocus",
            name: "Media",
            systemImage: "music.note.list",
            summary: "Music leads, with a smaller map and the transport bar alongside.",
            makeTree: { mediaFocus }
        ),
        Preset(
            id: "quad",
            name: "Four up",
            systemImage: "square.grid.2x2.fill",
            summary: "Map, gauges, music and weather in equal quarters.",
            makeTree: { quad }
        ),
        Preset(
            id: "mapOnly",
            name: "Just the map",
            systemImage: "location.north.line.fill",
            summary: "One tile, full screen. The least distracting option.",
            makeTree: { mapOnly }
        ),
        Preset(
            id: "gaugeCluster",
            name: "Gauges",
            systemImage: "gauge.with.dots.needle.50percent",
            summary: "Speed and heading up front, clock and weather to the side.",
            makeTree: { gaugeCluster }
        )
    ]

    public static func preset(id: String) -> Preset? {
        all.first { $0.id == id }
    }

    /// The layout a fresh install starts on.
    public static var `default`: Preset { all[0] }

    // MARK: - The trees

    public static var navigationFocus: LayoutTree {
        LayoutTree(root: .split(.horizontal, 0.66,
            .pane(.map),
            .split(.vertical, 0.55,
                .pane(.music),
                .pane(.gauges)
            )
        ))
    }

    public static var mediaFocus: LayoutTree {
        LayoutTree(root: .split(.horizontal, 0.58,
            .pane(.music),
            .split(.vertical, 0.62,
                .pane(.map),
                .pane(.nowPlaying)
            )
        ))
    }

    public static var quad: LayoutTree {
        LayoutTree(root: .split(.horizontal, 0.5,
            .split(.vertical, 0.5, .pane(.map), .pane(.gauges)),
            .split(.vertical, 0.5, .pane(.music), .pane(.weather))
        ))
    }

    public static var mapOnly: LayoutTree {
        LayoutTree(.map)
    }

    public static var gaugeCluster: LayoutTree {
        LayoutTree(root: .split(.horizontal, 0.55,
            .pane(.gauges),
            .split(.vertical, 0.4,
                .pane(.clock),
                .pane(.weather)
            )
        ))
    }
}

/// Screen sizes the presets are checked against.
///
/// Logical points in landscape, smallest first. `iPhoneSE` is not here because the app
/// requires iOS 26, which the last small-screen SE cannot run.
public enum ReferenceCanvas {
    /// iPhone 17 / 16 / 15 — the smallest canvas the app supports.
    public static let phone = LayoutSize(width: 852, height: 393)
    /// iPhone 17 Pro Max and similar.
    public static let phoneMax = LayoutSize(width: 932, height: 430)
    /// iPad Pro 11-inch.
    public static let tablet = LayoutSize(width: 1210, height: 834)
    /// Portrait on the smallest supported phone — where adaptation has to do real work.
    public static let phonePortrait = LayoutSize(width: 393, height: 852)

    public static let allLandscape = [phone, phoneMax, tablet]
}
