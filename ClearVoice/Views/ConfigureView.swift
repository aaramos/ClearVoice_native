import SwiftUI

struct ConfigureView: View {
    @ObservedObject var viewModel: ConfigureViewModel
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("How should we process the audio files?")
                    .font(.system(size: 22, weight: .semibold))

                Text("Select one enhancement method, decide whether to transcribe the results, and choose how many files to process at once.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)

            HStack(spacing: 22) {
                enhancementCard(for: .dfn)
                enhancementCard(for: .hybrid)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable Transcription", isOn: $viewModel.transcriptionEnabled)
                    .toggleStyle(.checkbox)
                    .font(.title3)

                Text("Transcription writes a Marathi transcript for each processed file. English translation stays off for this pass.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Processing Speed:")
                        .font(.title3.weight(.medium))

                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                viewModel.maxConcurrency = value
                            } label: {
                                Text("\(value)")
                                    .font(.headline.weight(.medium))
                                    .frame(width: 42, height: 34)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(viewModel.maxConcurrency == value ? Color.orange.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        viewModel.maxConcurrency == value ? Color.orange.opacity(0.8) : Color(nsColor: .separatorColor).opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(viewModel.maxConcurrency == value ? Color.orange : .primary)
                        }
                    }

                    Text("Choose how many files to process at once. Start with 2 unless the machine is clearly keeping up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(SecondaryActionButtonStyle())

                Spacer()

                Button("Next", action: onStart)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canStart)
            }
            .padding(.top, 6)
        }
    }

    private func enhancementCard(for method: EnhancementMethod) -> some View {
        Button {
            viewModel.enhancementMethod = method
        } label: {
            VStack(spacing: 14) {
                Image(systemName: method == .dfn ? "waveform.badge.magnifyingglass" : "waveform.path.ecg.rectangle")
                    .font(.system(size: 44))
                    .foregroundStyle(method == .dfn ? Color.purple.opacity(0.7) : Color.blue.opacity(0.9))

                VStack(spacing: 4) {
                    Text(method.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(method == .dfn ? "Deep Filter Net (DFN)" : "FFMPEG + Deep Filter Net")
                        .font(.title3)
                        .foregroundStyle(.primary)

                    Text(method.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 220)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 208)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(viewModel.enhancementMethod == method ? Color.orange.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        viewModel.enhancementMethod == method ? Color.orange.opacity(0.85) : Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
