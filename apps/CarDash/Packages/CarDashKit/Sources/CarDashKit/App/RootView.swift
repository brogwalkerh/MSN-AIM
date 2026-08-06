import SwiftUI
import CarDashCore

/// The app's root view.
///
/// Phase 0 deliberately renders almost nothing. Its job is to prove three things that
/// cannot be checked on the development machine: that the hand-written Xcode project
/// builds, that the local Swift packages resolve and link, and that `CarDashCore`'s
/// geometry works at runtime on a real device. The tiling engine replaces this in
/// Phase 1.
public struct RootView: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let canvas = LayoutRect(x: 0, y: 0, width: proxy.size.width, height: proxy.size.height)
            // Exercising Core from the app is the point: if this draws two correctly
            // proportioned tiles, the package graph is wired up.
            let (left, right) = canvas.inset(by: 12).divided(along: .horizontal, fraction: 0.62, gutter: 12)

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                placeholder("Map", subtitle: "Phase 3", rect: left)
                placeholder("Music", subtitle: "Phase 4", rect: right)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func placeholder(_ title: String, subtitle: String, rect: LayoutRect) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(0.06))
            .overlay {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

#Preview("Landscape", traits: .landscapeLeft) {
    RootView()
}
