import SwiftUI
import CarDashCore

/// The draggable bar between two tiles.
///
/// All the arithmetic lives in `CarDashCore.DividerDrag`; this view's only jobs are to
/// present a target big enough to hit while moving, and to capture the drag's starting
/// state exactly once so the maths stays absolute.
struct DividerHandle: View {
    let divider: SolvedDivider
    let isEditing: Bool
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    @Environment(\.dashTheme) private var theme
    @State private var drag: DividerDrag?
    @State private var didHitLimit = false

    private var isDragging: Bool { drag != nil }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(barColor)
                .frame(
                    width: divider.axis == .horizontal ? barThickness : barLength,
                    height: divider.axis == .horizontal ? barLength : barThickness
                )
                .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(width: divider.hitRect.width, height: divider.hitRect.height)
        // The visible bar is a few points wide; the target around it is finger-sized.
        // Without this the whole gesture area is only the capsule.
        .contentShape(Rectangle())
        .position(x: divider.hitRect.center.x, y: divider.hitRect.center.y)
        // A frozen divider — one whose subtrees cannot both shrink further — keeps its
        // appearance but stops responding, rather than following the finger and
        // snapping back.
        .gesture(dragGesture, isEnabled: divider.isAdjustable)
        .accessibilityElement()
        .accessibilityLabel("Resize divider")
        .accessibilityValue("\(Int((divider.fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            onChange(divider.fractionRange.clamp(divider.fraction + step))
            onEnd()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Captured once, at the start. Rebuilding it from the divider on every
                // update would make the arithmetic incremental, which is precisely the
                // bug DividerDrag exists to avoid.
                let drag = self.drag ?? DividerDrag(divider: divider)
                if self.drag == nil { self.drag = drag }

                let translation = drag.translation(
                    fromDX: value.translation.width,
                    dy: value.translation.height
                )
                onChange(drag.fraction(forTranslation: translation))

                let clamped = drag.isClamped(atTranslation: translation)
                if clamped != didHitLimit {
                    didHitLimit = clamped
                    if clamped { Haptics.limit() }
                }
            }
            .onEnded { _ in
                drag = nil
                didHitLimit = false
                onEnd()
            }
    }

    private var barColor: Color {
        if isDragging { return theme.dividerActive }
        if !divider.isAdjustable { return theme.divider.opacity(0.4) }
        return isEditing ? theme.accent.opacity(0.55) : theme.divider
    }

    /// Thicker and longer while editing, so the dividers read as things you can grab.
    private var barThickness: CGFloat {
        isDragging ? 6 : (isEditing ? 5 : 3)
    }

    private var barLength: CGFloat {
        let full = divider.axis == .horizontal ? divider.trackRect.height : divider.trackRect.width
        return isEditing || isDragging ? full * 0.5 : full * 0.28
    }
}
