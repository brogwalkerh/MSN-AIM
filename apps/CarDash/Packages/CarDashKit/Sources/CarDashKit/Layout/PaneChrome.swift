import SwiftUI
import CarDashCore

/// The frame around one tile, plus the controls that appear while rearranging.
///
/// Editing controls live here rather than in a separate overlay layer so they are
/// clipped to their own tile — on a four-up layout an overlay spanning the canvas would
/// put a remove button over the neighbouring map.
struct PaneChrome<Content: View>: View {
    let pane: Pane
    let title: String
    let sections: [SectionDescriptor]
    let isEditing: Bool
    let canSplit: Bool
    let canRemove: Bool
    let onSplit: (SplitAxis) -> Void
    let onReplace: (SectionID) -> Void
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.dashTheme) private var theme
    @Environment(\.dashDensity) private var density

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: density.paneCornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.tile, in: shape)
            .overlay {
                shape.strokeBorder(isEditing ? theme.accent.opacity(0.6) : theme.tileStroke,
                                   lineWidth: isEditing ? 2 : 1)
            }
            .clipShape(shape)
            .overlay { if isEditing { editingControls } }
            .animation(.snappy(duration: 0.2), value: isEditing)
    }

    private var editingControls: some View {
        ZStack {
            // Dims the live content so the controls are legible over a bright map,
            // and makes it obvious the dashboard is in a modal state.
            theme.background.opacity(0.55)

            VStack(spacing: 10) {
                Text(title)
                    .font(DashFont.paneTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Shrinks to just the essentials rather than overflowing when a tile is
                // small — a 2×2 layout on a phone leaves very little room here.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        replaceMenu
                        splitButton(.horizontal)
                        splitButton(.vertical)
                        removeButton
                    }
                    HStack(spacing: 6) {
                        replaceMenu
                        splitButton(.horizontal)
                        removeButton
                    }
                    HStack(spacing: 6) {
                        replaceMenu
                        removeButton
                    }
                }
            }
            .padding(8)
        }
        .transition(.opacity)
    }

    private var replaceMenu: some View {
        Menu {
            ForEach(sections) { section in
                Button {
                    onReplace(section.id)
                    Haptics.edit()
                } label: {
                    // Sections that are not built yet stay in the list but say so,
                    // rather than being silently absent or silently disappointing.
                    Label(
                        section.isComingSoon ? "\(section.title) (soon)" : section.title,
                        systemImage: section.systemImage
                    )
                }
                .disabled(section.id == pane.sectionID)
            }
        } label: {
            controlLabel("arrow.left.arrow.right", tint: theme.primaryText)
        }
        .accessibilityLabel("Change what this tile shows")
    }

    private func splitButton(_ axis: SplitAxis) -> some View {
        Button {
            onSplit(axis)
        } label: {
            controlLabel(
                axis == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2",
                tint: theme.primaryText
            )
        }
        .disabled(!canSplit)
        .opacity(canSplit ? 1 : 0.35)
        .accessibilityLabel(axis == .horizontal ? "Split side by side" : "Split top and bottom")
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            onRemove()
            Haptics.edit()
        } label: {
            controlLabel("trash", tint: theme.destructive)
        }
        .disabled(!canRemove)
        .opacity(canRemove ? 1 : 0.35)
        .accessibilityLabel("Remove this tile")
    }

    private func controlLabel(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.12), in: Circle())
            // 44 points is what fits inside a small tile; the surrounding padding brings
            // the practical target closer to the 60 the rest of the app uses.
            .contentShape(Circle())
    }
}
