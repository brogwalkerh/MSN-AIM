import SwiftUI
import CarDashCore

/// What a tile shows before its section is built.
///
/// Phase 1 is the tiling engine, so every tile is one of these. As sections land they
/// replace it one at a time — and it stays afterwards as the fallback for a layout that
/// names a section this build does not have, which is how an old saved dashboard
/// survives a rename instead of failing to load.
struct PanePlaceholderView: View {
    let pane: Pane

    @Environment(\.dashTheme) private var theme

    private var entry: SectionCatalog.Entry? {
        SectionCatalog.entry(for: pane.sectionID)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: SectionCatalog.systemImage(for: pane.sectionID))
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(theme.secondaryText)

            Text(SectionCatalog.title(for: pane.sectionID))
                .font(DashFont.value(22))
                .foregroundStyle(theme.primaryText)

            if let entry {
                Text(entry.comingIn.map { "Arrives in \($0)" } ?? entry.blurb)
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("This layout was saved with a tile this version does not have.")
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Small tiles cannot show all of this; dropping the caption beats clipping it.
        .lineLimit(2)
        .minimumScaleFactor(0.6)
    }
}
