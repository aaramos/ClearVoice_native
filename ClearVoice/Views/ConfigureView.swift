import SwiftUI

struct ConfigureView: View {
    @ObservedObject var viewModel: ConfigureViewModel
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        StepCard(
            title: "Configure",
            detail: "Choose how ClearVoice should enhance the audio, whether to transcribe it, and how many files to process at once."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                currentPlanCard
                enhancementCard
                processingOptionsCard
                speedCard

                Text(viewModel.helperText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack {
                    Button("Back", action: onBack)
                    Spacer()
                    Button("Next", action: onStart)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canStart)
                }
            }
        }
    }

    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Plan")
                .font(.headline)

            HStack(spacing: 12) {
                summaryMetric(label: "Source", value: "Marathi")
                Divider()
                summaryMetric(label: "Enhancement", value: viewModel.enhancementMethod.title)
                Divider()
                summaryMetric(label: "Transcription", value: viewModel.transcriptionEnabled ? "On" : "Off")
            }
        }
        .cardStyle()
    }

    private var enhancementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enhancement Method")
                .font(.headline)

            Picker("Enhancement Method", selection: $viewModel.enhancementMethod) {
                ForEach(EnhancementMethod.allCases) { method in
                    Text(method.title)
                        .tag(method)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.enhancementMethod.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var processingOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Processing Options")
                .font(.headline)

            Toggle("Transcribe audio", isOn: $viewModel.transcriptionEnabled)

            Text("Transcription writes a Marathi transcript into each file’s output folder. Translation stays off in this UI pass.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Processing Speed")
                .font(.headline)

            Stepper(value: $viewModel.maxConcurrency, in: 1...5) {
                HStack {
                    Text("Files at once")
                    Spacer()
                    Text("\(viewModel.maxConcurrency)")
                        .monospacedDigit()
                }
            }

            Text(viewModel.advancedSummary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func summaryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}
