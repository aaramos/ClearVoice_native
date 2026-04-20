import SwiftUI

struct ImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    let onNext: () -> Void

    var body: some View {
        StepCard(
            title: "Import",
            detail: "Phase 1 establishes the shell only, so the import experience is intentionally scaffolded."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                placeholderPanel(title: "Source Folder", detail: viewModel.sourceFolderSummary)
                placeholderPanel(title: "Output Folder", detail: viewModel.outputFolderSummary)
                placeholderPanel(title: "Scanner + Validation", detail: viewModel.fileSummary)

                Spacer()

                HStack {
                    Spacer()
                    Button("Next", action: onNext)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func placeholderPanel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
