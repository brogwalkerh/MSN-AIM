import SwiftUI
import CarDashCore

/// Switching between saved dashboards, and making new ones from the presets.
struct LayoutLibrarySheet: View {
    let model: LayoutModel

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: UUID?
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Your layouts") {
                    ForEach(model.documents) { document in
                        row(for: document)
                    }
                }

                Section {
                    ForEach(LayoutPresets.all) { preset in
                        Button {
                            model.addDocument(from: preset)
                            dismiss()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                    Text(preset.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: preset.systemImage)
                            }
                        }
                    }
                } header: {
                    Text("Start from a preset")
                } footer: {
                    Text("Adds a new layout. Your existing ones are untouched.")
                }
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename layout", isPresented: renamingBinding) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let renaming { model.rename(renaming, to: draftName) }
                    renaming = nil
                }
            }
        }
        // A sheet is a parked-car interaction. It is presented at a comfortable size
        // rather than full screen so the dashboard stays visible behind it.
        .presentationDetents([.medium, .large])
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func row(for document: LayoutDocument) -> some View {
        Button {
            model.selectDocument(document.id)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                    Text(summary(of: document))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if document.id == model.activeID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.deleteDocument(document.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.documents.count <= 1)

            Button {
                draftName = document.name
                renaming = document.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.gray)
        }
    }

    private func summary(of document: LayoutDocument) -> String {
        let sections = document.variants.phoneLandscape.sectionIDs
            .map { SectionCatalog.title(for: $0) }
        let portrait = document.variants.phonePortrait == nil ? "" : " · custom portrait"
        return sections.joined(separator: ", ") + portrait
    }
}
