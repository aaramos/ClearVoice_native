import SwiftUI

struct DependencySetupView: View {
    @ObservedObject var viewModel: DependencySetupViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.stage.title)
                    .font(.system(size: 32, weight: .bold))
                Text(viewModel.stage.message)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Setup hit a problem", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Quit ClearVoice", action: onQuit)
                            .buttonStyle(.bordered)
                        Button("Retry Setup") {
                            viewModel.retry()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.dependencies) { dependency in
                    DependencyStatusRow(record: dependency)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Managed install location", systemImage: "externaldrive.connected.to.line.below")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.installRootDescription)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: 840)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task {
            viewModel.start()
        }
    }
}

private struct DependencyStatusRow: View {
    let record: ToolDependencyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(record.descriptor.displayName)
                            .font(.headline)
                        Spacer()
                        Text(statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(iconColor)
                    }

                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            switch record.status {
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress.fractionCompleted)
                    Text(progressText(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .checking, .extracting, .verifying:
                ProgressView()
                    .controlSize(.small)
            default:
                EmptyView()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var statusLabel: String {
        switch record.status {
        case .waiting:
            "Waiting"
        case .checking:
            "Checking"
        case .installed(_, _, .managedByClearVoice):
            "Installed"
        case .installed(_, _, .existingSystemInstall):
            "Already on This Mac"
        case .missing:
            "Missing"
        case .downloading:
            "Downloading"
        case .extracting:
            "Unpacking"
        case .verifying:
            "Verifying"
        case .failed:
            "Needs Attention"
        }
    }

    private var detailText: String {
        switch record.status {
        case .waiting:
            return record.descriptor.purpose
        case .checking:
            return "Looking for an installed copy of \(record.descriptor.displayName) and checking that it responds correctly."
        case .installed(let version, let location, let source):
            let prefix = switch source {
            case .managedByClearVoice:
                "Ready for ClearVoice"
            case .existingSystemInstall:
                "Available on this Mac"
            }

            return "\(prefix): \(version) at \(ManagedToolPaths.userFacingPath(location))"
        case .missing:
            return "\(record.descriptor.displayName) is missing. ClearVoice will download and configure it automatically."
        case .downloading:
            return "Downloading the official \(record.descriptor.displayName) package."
        case .extracting:
            return "Unpacking the downloaded files and putting them in ClearVoice’s managed tools folder."
        case .verifying:
            return "Running a quick health check to make sure the tool launches correctly."
        case .failed(let message):
            return message
        }
    }

    private var iconName: String {
        switch record.status {
        case .installed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .missing:
            "arrow.down.circle"
        case .downloading:
            "arrow.down.circle.fill"
        case .extracting, .verifying, .checking:
            "gearshape.2.fill"
        case .waiting:
            "circle.dotted"
        }
    }

    private var iconColor: Color {
        switch record.status {
        case .installed:
            .green
        case .failed:
            .orange
        case .missing:
            .secondary
        case .downloading, .extracting, .verifying, .checking:
            .blue
        case .waiting:
            .secondary
        }
    }

    private func progressText(_ progress: ToolDownloadProgress) -> String {
        let received = ByteCountFormatter.string(fromByteCount: progress.receivedBytes, countStyle: .file)
        let total = progress.expectedBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "unknown size"

        let speed = progress.bytesPerSecond > 0
            ? "\(ByteCountFormatter.string(fromByteCount: Int64(progress.bytesPerSecond), countStyle: .file))/s"
            : "calculating speed"

        let eta: String
        if let estimatedTimeRemaining = progress.estimatedTimeRemaining,
           estimatedTimeRemaining.isFinite,
           estimatedTimeRemaining > 0 {
            eta = "ETA \(formattedTime(estimatedTimeRemaining))"
        } else {
            eta = "Finishing soon"
        }

        return "\(received) of \(total) • \(speed) • \(eta)"
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded()), 1)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }
}
