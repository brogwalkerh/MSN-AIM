import SwiftUI
import UniformTypeIdentifiers
import CarDashCore

/// Switching between saved dashboards, making new ones from the presets, and moving them
/// between devices.
struct LayoutLibrarySheet: View {
    let model: LayoutModel
    let registry: SectionRegistry

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: UUID?
    @State private var draftName = ""
    @State private var importing = false
    @State private var importProblem: String?

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

                Section {
                    Button {
                        importing = true
                    } label: {
                        Label("Import a layout…", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    // Worth saying, because it is the sort of thing people reasonably worry
                    // about before sending a file to someone.
                    Text("Touch and hold a layout to share it. A shared layout contains only the arrangement — no contacts, accounts or trip data.")
                }
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $importing,
                // JSON as well as our own type: a layout that has been through email or a
                // chat app often arrives with its extension or UTI rewritten, and refusing
                // to even open it would be baffling. The contents are validated either way.
                allowedContentTypes: [.cardashLayout, .json]
            ) { result in
                importLayout(from: result)
            }
            .alert(
                "Couldn't import that",
                isPresented: Binding(
                    get: { importProblem != nil },
                    set: { if !$0 { importProblem = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importProblem = nil }
            } message: {
                Text(importProblem ?? "")
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
        // A context menu rather than a swipe action: `swipeActions` expects Buttons, and a
        // ShareLink placed there is not reliably rendered — which would be a share control
        // that silently is not there, rather than one that fails visibly.
        .contextMenu {
            if let file = try? LayoutFile(document: document) {
                ShareLink(item: file, preview: SharePreview(document.name)) {
                    Label("Share layout…", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func importLayout(from result: Result<URL, any Error>) {
        guard case .success(let url) = result else {
            if case .failure(let error) = result {
                importProblem = error.localizedDescription
            }
            return
        }

        // A file picked from iCloud Drive or another app's container is outside this app's
        // sandbox. Without the security scope the read fails with a permissions error that
        // reads like the file is corrupt.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            try model.importDocument(from: try Data(contentsOf: url))
            Haptics.edit()
            dismiss()
        } catch let error as LayoutTransfer.ImportError {
            importProblem = error.userFacingMessage
        } catch {
            importProblem = "That file couldn't be read."
        }
    }

    private func summary(of document: LayoutDocument) -> String {
        let sections = document.variants.phoneLandscape.sectionIDs
            .map { registry.title(for: $0) }
        let portrait = document.variants.phonePortrait == nil ? "" : " · custom portrait"
        return sections.joined(separator: ", ") + portrait
    }
}
