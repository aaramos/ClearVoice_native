import SwiftUI
import UniformTypeIdentifiers

struct FolderPicker: View {
    let title: String
    let subtitle: String
    let selection: URL?
    let buttonTitle: String
    let onSelect: (URL) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(buttonTitle, action: chooseFolder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(selection?.path(percentEncoded: false) ?? "No folder selected")
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(selection == nil ? .secondary : .primary)

                Text("Drag and drop a folder here or use the picker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1, dash: isDropTargeted ? [] : [6, 5])
                    )
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.urls.first {
            onSelect(url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard
                let data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                return
            }

            DispatchQueue.main.async {
                onSelect(url)
            }
        }

        return true
    }
}
