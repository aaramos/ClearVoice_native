import SwiftUI

struct ProcessingModeToggleRow: View {
    let label: String
    @Binding var mode: ProcessingMode
    let isEnabled: Bool
    let apiKeyPresent: Bool
    var badgeSuffix: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer()
            badge(text: badgeText, tint: badgeTint)

            if apiKeyPresent {
                Toggle("", isOn: isCloudBinding)
                    .labelsHidden()
                    .disabled(!isEnabled)
            }
        }
    }

    private var isCloudBinding: Binding<Bool> {
        Binding(
            get: { mode == .cloud },
            set: { mode = $0 ? .cloud : .local }
        )
    }

    private var badgeText: String {
        if !apiKeyPresent {
            return "Requires key"
        }

        let base = mode == .cloud ? "Gemini" : "On-device"

        if let badgeSuffix, !badgeSuffix.isEmpty {
            return "\(base) · \(badgeSuffix)"
        }

        if !isEnabled {
            return "\(base) · auto"
        }

        return base
    }

    private var badgeTint: Color {
        if !apiKeyPresent {
            return .orange
        }

        return mode == .cloud ? .blue : .green
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
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
