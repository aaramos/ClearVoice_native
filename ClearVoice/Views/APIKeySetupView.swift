import SwiftUI

struct APIKeySetupView: View {
    @ObservedObject var viewModel: AppLaunchViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 24) {
                header
                keyEntryCard
                actions
            }
            .padding(32)
            .frame(maxWidth: 640)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect Gemini", systemImage: "key.horizontal.fill")
                .font(.system(size: 28, weight: .semibold))
            Text("Enter your Gemini API key once and ClearVoice will save it in your macOS Keychain for this user on this Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var keyEntryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gemini API Key")
                    .font(.headline)
                SecureField("AIza...", text: $viewModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(viewModel.saveAPIKey)
                Text("ClearVoice keeps the saved key out of plain-text settings and project files. Developers can still override it with `GEMINI_API_KEY` when launching from a shell.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let submissionErrorMessage = viewModel.submissionErrorMessage {
                    Text(submissionErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Stored On This Mac", systemImage: "lock.shield.fill")
        }
    }

    private var actions: some View {
        HStack {
            Button("Quit ClearVoice", action: onQuit)
            Spacer()
            Button("Use local processing only →", action: viewModel.skipToLocalMode)
            Button("Save and Continue", action: viewModel.saveAPIKey)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSubmitAPIKey)
        }
    }
}
