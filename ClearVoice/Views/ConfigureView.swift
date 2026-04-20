import SwiftUI

struct ConfigureView: View {
    @ObservedObject var viewModel: ConfigureViewModel
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        StepCard(
            title: "Configure",
            detail: "The settings model is in place now so later phases can add real controls without changing navigation."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    configRow(label: "Intensity", value: viewModel.intensity.band.rawValue.capitalized)
                    configRow(label: "Input Language", value: viewModel.inputLanguage.displayName)
                    configRow(label: "Output Language", value: viewModel.outputLanguage.displayName)
                }

                Text(viewModel.helperText)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Button("Back", action: onBack)
                    Spacer()
                    Button("Start", action: onStart)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.headline)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
