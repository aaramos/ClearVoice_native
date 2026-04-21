import SwiftUI

struct DependencySetupConsentView: View {
    let dependencies: [ToolDependencyDescriptor]
    let installRootDescription: String
    let onContinue: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set Up ClearVoice")
                    .font(.system(size: 34, weight: .bold))
                Text("ClearVoice needs two local audio tools before it can enhance files. With your permission, it will check whether they already exist on this Mac and download official copies only if they’re missing.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(dependencies) { dependency in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dependency.displayName)
                            .font(.headline)
                        Text(dependency.purpose)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Install location", systemImage: "externaldrive.connected.to.line.below")
                    .font(.subheadline.weight(.semibold))
                Text(installRootDescription)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("ClearVoice will verify each tool after download and show progress while it works. You won’t need Terminal for any part of setup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Quit ClearVoice", action: onQuit)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Continue Setup", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

