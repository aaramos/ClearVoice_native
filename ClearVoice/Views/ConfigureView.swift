import SwiftUI

struct ConfigureView: View {
    @ObservedObject var viewModel: ConfigureViewModel
    let onBack: () -> Void
    let onStart: () -> Void
    @State private var showsAdvanced = true

    var body: some View {
        StepCard(
            title: "Configure",
            detail: "Choose how aggressively ClearVoice should clean the audio and which languages it should use during transcription and translation."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                audioSettingsCard
                languageSettingsCard
                processingSettingsCard
                advancedSettingsCard

                Text(viewModel.helperText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !viewModel.canStart {
                    Label("This language requires Gemini transcription. Add a Gemini key to continue.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

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

            Picker("Output Language", selection: outputLanguageBinding) {
                ForEach(viewModel.outputLanguageOptions) { language in
                    Text(language.displayName)
                        .tag(language.id)
                }
            }
        }
        .cardStyle()
    }

    private var processingSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            Text("Processing")
                .font(.headline)

            if viewModel.apiKeyPresent {
                Text(viewModel.processingSummaryText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ProcessingModeToggleRow(
                    label: "Transcription",
                    mode: $viewModel.transcriptionMode,
                    isEnabled: viewModel.canToggleTranscription,
                    apiKeyPresent: true,
                    badgeSuffix: transcriptionBadgeSuffix
                )

                ProcessingModeToggleRow(
                    label: "Translation",
                    mode: $viewModel.translationMode,
                    isEnabled: viewModel.canToggleTranslation,
                    apiKeyPresent: true
                )

                ProcessingModeToggleRow(
                    label: "Summarization",
                    mode: .constant(viewModel.summarizationMode),
                    isEnabled: false,
                    apiKeyPresent: true
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("All steps run on this Mac")
                        .font(.subheadline.weight(.medium))
                    Button("Add Gemini key →", action: viewModel.requestAPIKeySetup)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }

                staticProcessingRow(label: "Transcription", badgeText: "On-device", tint: .green)
                staticProcessingRow(label: "Translation", badgeText: "On-device", tint: .green)
                staticProcessingRow(label: "Summarization", badgeText: "Requires Gemini key", tint: .orange)
            }
        }
        .cardStyle()
    }

    private var advancedSettingsCard: some View {
        DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                Stepper(value: $viewModel.maxConcurrency, in: 1...8) {
                    LabeledContent("Parallel Files") {
                        Text("\(viewModel.maxConcurrency)")
                            .monospacedDigit()
                    }
                }

                Toggle("Preserve channels when possible", isOn: $viewModel.preserveChannels)

                Text(viewModel.advancedSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        }
        .cardStyle()
    }

    private var transcriptionBadgeSuffix: String? {
        var suffixes: [String] = []

        if !viewModel.canToggleTranscription {
            suffixes.append("auto")
        }

        if viewModel.shouldOptimizeUpload && viewModel.transcriptionMode == .cloud {
            suffixes.append("audio optimized for upload")
        }

        return suffixes.isEmpty ? nil : suffixes.joined(separator: " · ")
    }

    private func staticProcessingRow(label: String, badgeText: String, tint: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(badgeText)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.12))
                )
        }
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

    private var outputLanguageBinding: Binding<String> {
        Binding(
            get: { viewModel.outputLanguage.id },
            set: { viewModel.selectOutputLanguage(id: $0) }
        )
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}
