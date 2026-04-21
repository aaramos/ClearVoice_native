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
        Button(action: chooseFolder) {
            VStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let selection {
                    Text(selection.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(buttonTitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 178)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isDropTargeted ? Color.blue.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
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
