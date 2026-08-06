import SwiftUI
import CarDashCore

/// A tile whose section has not been built yet.
struct SectionPlaceholderView: View {
    let title: String
    let systemImage: String
    let detail: String
    let environment: PaneEnvironment

    @Environment(\.dashTheme) private var theme

    var body: some View {
        VStack(spacing: environment.isCompact ? 4 : 8) {
            Image(systemName: systemImage)
                .font(.system(size: environment.isCompact ? 20 : 30, weight: .regular))
                .foregroundStyle(theme.secondaryText)

            Text(title)
                .font(DashFont.value(environment.isCompact ? 17 : 22))
                .foregroundStyle(theme.primaryText)

            if !environment.isCompact {
                Text(detail)
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
    }
}

/// A tile naming a section this build does not have.
///
/// The reason a saved layout survives a renamed or removed section: the document decodes
/// with the unknown identifier intact and the tile offers to be replaced, rather than the
/// whole dashboard failing to load over one tile.
struct MissingSectionView: View {
    let sectionID: SectionID
    let onReplace: () -> Void

    @Environment(\.dashTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondaryText)

            Text("“\(sectionID.rawValue)”")
                .font(DashFont.value(17))
                .foregroundStyle(theme.primaryText)

            Text("This layout was saved with a tile this version doesn't have.")
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)

            Button("Choose something else", action: onReplace)
                .font(DashFont.label())
                .foregroundStyle(theme.background)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(theme.accent, in: Capsule())
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .minimumScaleFactor(0.6)
    }
}
