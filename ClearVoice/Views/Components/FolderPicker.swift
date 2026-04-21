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
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.10))
                        .frame(width: 72, height: 72)

                    Image(systemName: "folder.fill.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.85))
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.92))

                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(Color.black.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }

                if let selection {
                    Text(selection.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.blue.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.08))
                        )
                } else {
                    Text(buttonTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 248)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isDropTargeted ? Color.blue.opacity(0.85) : Color.blue.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
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
