import SwiftUI
import UniformTypeIdentifiers
import CarDashCore

public extension UTType {
    /// The `.cardash` document type.
    ///
    /// `exportedAs` rather than `importedAs`: this app defines the format, and the declaration
    /// lives in its Info.plist. Without that declaration the type still resolves, but the share
    /// sheet has no icon or name for it and Files shows it as a generic document.
    static var cardashLayout: UTType {
        UTType(exportedAs: LayoutTransfer.contentType, conformingTo: .json)
    }
}

/// A layout on its way to the share sheet.
///
/// `Transferable` rather than writing a temporary file and sharing its URL. The URL approach
/// works but leaves the file behind in the container, and the cleanup is easy to get wrong in
/// exactly the way that accumulates junk over months of use.
struct LayoutFile: Transferable {
    let name: String
    let data: Data

    init(document: LayoutDocument, now: Date = Date()) throws {
        self.name = LayoutTransfer.filename(for: document)
        self.data = try LayoutTransfer.export(document, now: now)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .cardashLayout) { file in
            file.data
        }
        .suggestedFileName { $0.name }
    }
}
