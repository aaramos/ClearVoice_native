import SwiftUI

struct ConfigureView: View {
    @ObservedObject var viewModel: ConfigureViewModel
    let onBack: () -> Void
    let onStart: () -> Void
    @State private var showsAdvanced = true

    var body: some View {
        StepCard(
            title: "Configure",
            detail: "Choose how aggressively ClearVoice should clean the audio, which language to transcribe, and how many local jobs to run at once."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                audioSettingsCard
                languageSettingsCard
                advancedSettingsCard

                Text(viewModel.helperText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack {
                    Button("Back", action: onBack)
                    Spacer()
                    Button("Start Processing", action: onStart)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canStart)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Plan")
                .font(.headline)

            HStack(spacing: 12) {
                summaryMetric(
                    label: "Intensity",
                    value: viewModel.intensity.band.rawValue.capitalized
                )
                Divider()
                summaryMetric(
                    label: "Source",
                    value: viewModel.inputLanguage.displayName
                )
                Divider()
                summaryMetric(
                    label: "Output",
                    value: viewModel.outputLanguage.displayName
                )
            }
        }
        .cardStyle()
    }

    private var audioSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audio Cleanup")
                .font(.headline)

            Picker("Intensity", selection: intensityBandBinding) {
                ForEach(Intensity.Band.allCases, id: \.self) { band in
                    Text(band.rawValue.capitalized)
                        .tag(band)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.intensityDescription)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var languageSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Language Workflow")
                .font(.headline)

            Picker("Input Language", selection: inputLanguageBinding) {
                ForEach(viewModel.inputLanguageOptions) { language in
                    Text(language.displayName)
                        .tag(language.id)
                }
            }

            LabeledContent("Output Language") {
                Text(viewModel.outputLanguage.displayName)
                    .foregroundStyle(.secondary)
            }

            Text("English translation is temporarily disabled while we validate local Marathi transcription.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var advancedSettingsCard: some View {
        DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                Stepper(value: $viewModel.maxConcurrency, in: 1...5) {
                    LabeledContent("Parallel Files") {
                        Text("\(viewModel.maxConcurrency)")
                            .monospacedDigit()
                    }
                }

                Text(viewModel.advancedSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
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
    }

    private var intensityBandBinding: Binding<Intensity.Band> {
        Binding(
            get: { viewModel.intensityBand },
            set: { viewModel.intensityBand = $0 }
        )
    }

    private var inputLanguageBinding: Binding<String> {
        Binding(
            get: { viewModel.inputLanguage.id },
            set: { viewModel.selectInputLanguage(id: $0) }
        )
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
