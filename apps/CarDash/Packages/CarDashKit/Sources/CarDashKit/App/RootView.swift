import SwiftUI
import CarDashCore

/// The app's root view.
public struct RootView: View {
    @State private var model: LayoutModel

    @MainActor
    public init() {
        // Falling back to an in-memory store means a phone that cannot write to
        // Application Support — full disk, restricted container — still runs, with
        // layouts that last until the app quits. Refusing to launch would be worse.
        let store: any LayoutStore = (try? FileLayoutStore()) ?? InMemoryLayoutStore()
        _model = State(initialValue: LayoutModel(store: store))
    }

    /// For previews and tests.
    @MainActor
    public init(model: LayoutModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        DashboardView(model: model)
            .environment(\.dashTheme, .night)
    }
}

#Preview("Dashboard", traits: .landscapeLeft) {
    RootView(model: previewModel())
}

#Preview("Rearranging", traits: .landscapeLeft) {
    RootView(model: previewModel(editing: true))
}

#Preview("Portrait (adapted)") {
    RootView(model: previewModel(tree: LayoutPresets.quad))
}

@MainActor
private func previewModel(
    tree: LayoutTree = LayoutPresets.navigationFocus,
    editing: Bool = false
) -> LayoutModel {
    let document = LayoutDocument(name: "Preview", tree: tree, now: Date())
    let model = LayoutModel(store: InMemoryLayoutStore([document]))
    model.isEditing = editing
    return model
}
