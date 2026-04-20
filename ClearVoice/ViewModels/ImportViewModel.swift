import Foundation

@MainActor
final class ImportViewModel: ObservableObject {
    @Published var sourceFolderSummary = "Source folder selection lands in Phase 2."
    @Published var outputFolderSummary = "Output folder selection lands in Phase 2."
    @Published var fileSummary = "Scanner, validation, and drag-and-drop land in Phase 2."

    var canProceed: Bool {
        true
    }
}
