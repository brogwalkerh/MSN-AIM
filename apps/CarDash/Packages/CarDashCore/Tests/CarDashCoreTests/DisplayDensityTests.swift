import Foundation
import Testing
@testable import CarDashCore

@Suite("Display density")
struct DisplayDensityTests {
    @Test("The default is the middle setting, not the loosest")
    func defaultLevel() {
        #expect(DisplayDensity.default == .standard)
        // The values that shipped for the first five phases are now `cosy`, so anyone who
        // preferred the old look has somewhere to go.
        #expect(DisplayDensity.cosy.gutter == 10)
        #expect(DisplayDensity.cosy.panePadding == 10)
        #expect(DisplayDensity.cosy.canvasInset == 10)
    }

    @Test("LayoutMetrics reports the default density, so untouched call sites follow it")
    func metricsTrackDefault() {
        #expect(LayoutMetrics.gutter == DisplayDensity.default.gutter)
        #expect(LayoutMetrics.paneCornerRadius == DisplayDensity.default.paneCornerRadius)
        #expect(LayoutMetrics.dividerHitSlop == DisplayDensity.default.dividerHitSlop)
    }

    // The ordering is the whole point of the type. A "compact" setting that was looser than
    // "standard" in any one dimension would be a silent nonsense.
    @Test("Every metric tightens monotonically from cosy to compact")
    func monotonic() {
        let levels: [DisplayDensity] = [.cosy, .standard, .compact]

        for (looser, tighter) in zip(levels, levels.dropFirst()) {
            #expect(tighter.gutter < looser.gutter, "\(tighter) gutter")
            #expect(tighter.paneCornerRadius < looser.paneCornerRadius, "\(tighter) corner radius")
            #expect(tighter.panePadding < looser.panePadding, "\(tighter) padding")
            #expect(tighter.canvasInset < looser.canvasInset, "\(tighter) canvas inset")
        }
    }

    // A corner radius larger than the padding pulls content into the arc, which clips text at
    // the corners of every tile. It is the specific mistake this type exists to prevent, and
    // it is invisible until something happens to be written in a corner.
    @Test("Corner radius never exceeds what the padding can clear", arguments: DisplayDensity.allCases)
    func cornersDoNotClipContent(density: DisplayDensity) {
        // The arc intrudes by r - r/√2 at 45°, which is what the padding has to absorb.
        let intrusion = density.paneCornerRadius * (1 - 1 / Double(2).squareRoot())
        #expect(density.panePadding >= intrusion, "\(density) clips its own content")
    }

    @Test("Values are all positive and finite", arguments: DisplayDensity.allCases)
    func sane(density: DisplayDensity) {
        for value in [density.gutter, density.paneCornerRadius, density.panePadding,
                      density.canvasInset, density.dividerHitSlop] {
            #expect(value > 0)
            #expect(value.isFinite)
        }
    }

    // As the gutter tightens the visible bar gets thinner, and the invisible target has to
    // grow to compensate — otherwise "compact" would mean "cannot resize tiles in a car".
    @Test("The divider stays grabbable at every density", arguments: DisplayDensity.allCases)
    func dividerTargetSurvivesTightening(density: DisplayDensity) {
        #expect(density.dividerTarget >= DisplayDensity.minimumDividerTarget,
                "\(density) divider target is \(density.dividerTarget)")
    }

    @Test("Tightening the gutter does not shrink the divider target")
    func slopCompensates() {
        #expect(DisplayDensity.compact.dividerHitSlop >= DisplayDensity.standard.dividerHitSlop)
        #expect(DisplayDensity.standard.dividerHitSlop >= DisplayDensity.cosy.dividerHitSlop)
    }

    // Persisted as a bare string, so the stored value has to be stable. Renaming a case would
    // silently reset everyone's setting on upgrade.
    @Test("Raw values are the stable persisted form")
    func rawValues() {
        #expect(DisplayDensity.cosy.rawValue == "cosy")
        #expect(DisplayDensity.standard.rawValue == "standard")
        #expect(DisplayDensity.compact.rawValue == "compact")
        #expect(DisplayDensity(rawValue: "standard") == .standard)
        #expect(DisplayDensity(rawValue: "spacious") == nil, "callers fall back to the default")
    }

    @Test("Round trips through JSON")
    func codable() throws {
        for density in DisplayDensity.allCases {
            let encoded = try JSONEncoder().encode(density)
            let decoded = try JSONDecoder().decode(DisplayDensity.self, from: encoded)
            #expect(decoded == density)
        }
    }

    @Test("Every level is presentable in a picker", arguments: DisplayDensity.allCases)
    func presentation(density: DisplayDensity) {
        #expect(!density.title.isEmpty)
        #expect(!density.blurb.isEmpty)
    }
}

// The reason a density setting is worth having at all: it has to actually change the
// arrangement, and it must not break the arrangements that already exist.
@Suite("Density drives the layout engine")
struct DensityLayoutTests {
    private let canvas = LayoutRect(origin: .zero, size: ReferenceCanvas.phoneMax)

    @Test("A tighter gutter gives the tiles the space back")
    func tighterGutterWidensTiles() throws {
        var tree = LayoutTree(.map)
        _ = try tree.split(tree.panes[0].id, axis: .horizontal, inserting: .clock)

        let cosy = LayoutSolver.solve(tree, in: canvas, gutter: DisplayDensity.cosy.gutter)
        let compact = LayoutSolver.solve(tree, in: canvas, gutter: DisplayDensity.compact.gutter)

        let cosyWidth = try #require(cosy.paneRects.values.map(\.size.width).max())
        let compactWidth = try #require(compact.paneRects.values.map(\.size.width).max())
        #expect(compactWidth > cosyWidth)

        // Two tiles, one gutter: exactly the difference in gutter is returned to the tiles.
        let recovered = DisplayDensity.cosy.gutter - DisplayDensity.compact.gutter
        #expect(abs((compactWidth - cosyWidth) - recovered / 2) < 1e-9)
    }

    // A saved layout is a tree of section ids and fractions; it holds no spacing at all. This
    // asserts that, because if density ever leaked into the document format then changing the
    // setting would rewrite every saved layout.
    @Test("Density is not part of a saved layout")
    func densityIsNotPersisted() throws {
        let document = LayoutPresets.default.document(now: Date(timeIntervalSince1970: 0))
        let encoded = try LayoutCodec.encode(document)
        let json = try #require(String(data: encoded, encoding: .utf8))

        for term in ["gutter", "density", "cornerRadius", "padding", "inset"] {
            #expect(!json.localizedCaseInsensitiveContains(term), "\(term) leaked into the document")
        }
    }

    // The minimum sizes were chosen when the gutter was 10. Tightening it only ever frees
    // space, so anything that fitted before still fits — but that is worth proving rather
    // than reasoning about, because the presets are what the app comes up on.
    @Test("Every preset still fits at every density", arguments: DisplayDensity.allCases)
    func presetsFitAtEveryDensity(density: DisplayDensity) throws {
        for preset in LayoutPresets.all {
            let tree = preset.makeTree()
            for canvas in ReferenceCanvas.allLandscape {
                let minimum = tree.minimumSize(
                    policy: SectionMetrics.builtInPolicy,
                    gutter: density.gutter
                )
                #expect(minimum.width <= canvas.width,
                        "\(preset.name) at \(density) needs \(minimum.width) of \(canvas.width)")
                #expect(minimum.height <= canvas.height,
                        "\(preset.name) at \(density) needs \(minimum.height) of \(canvas.height)")
            }
        }
    }
}
