import Foundation

@MainActor
final class DependencySetupViewModel: ObservableObject {
    enum Stage: Equatable {
        case checking
        case installing
        case finalizing

        var title: String {
            switch self {
            case .checking:
                "Checking Dependencies"
            case .installing:
                "Installing Dependencies"
            case .finalizing:
                "Opening ClearVoice"
            }
        }

        var message: String {
            switch self {
            case .checking:
                "ClearVoice is checking whether FFmpeg and DeepFilterNet are already available on this Mac."
            case .installing:
                "Missing tools are being downloaded, unpacked, and verified one at a time."
            case .finalizing:
                "Setup is complete. ClearVoice is switching into the main app."
            }
        }
    }

    @Published private(set) var stage: Stage = .checking
    @Published private(set) var dependencies: [ToolDependencyRecord]
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isComplete = false

    let installRootDescription: String

    private let manager: DependencySetupManager
    private let onReady: @MainActor () -> Void
    private var runTask: Task<Void, Never>?

    init(
        manager: DependencySetupManager = DependencySetupManager(),
        installRootDescription: String = ManagedToolPaths.userFacingPath(ManagedToolPaths.toolsRoot()),
        onReady: @escaping @MainActor () -> Void
    ) {
        self.manager = manager
        self.installRootDescription = installRootDescription
        self.onReady = onReady
        self.dependencies = manager.plannedDependencies.map {
            ToolDependencyRecord(descriptor: $0, status: .waiting)
        }
    }

    deinit {
        runTask?.cancel()
    }

    func start() {
        guard runTask == nil else { return }

        runTask = Task { [weak self] in
            await self?.runSetup()
        }
    }

    func retry() {
        runTask?.cancel()
        runTask = nil
        stage = .checking
        errorMessage = nil
        isRunning = false
        isComplete = false
        dependencies = dependencies.map { ToolDependencyRecord(descriptor: $0.descriptor, status: .waiting) }
        start()
    }

    private func runSetup() async {
        errorMessage = nil
        isComplete = false
        isRunning = true
        stage = .checking

        let inspectionResults = await manager.inspectAll()
        apply(records: inspectionResults)

        let missingDependencies = inspectionResults.filter { record in
            if case .missing = record.status {
                return true
            }
            return false
        }

        if missingDependencies.isEmpty {
            await completeSetup()
            return
        }

        stage = .installing

        for record in missingDependencies {
            do {
                let installedRecord = try await manager.install(record.descriptor) { [weak self] status in
                    await MainActor.run {
                        self?.updateStatus(status, for: record.descriptor.id)
                    }
                }

                updateStatus(installedRecord.status, for: record.descriptor.id)
            } catch {
                updateStatus(.failed(error.localizedDescription), for: record.descriptor.id)
                errorMessage = error.localizedDescription
                isRunning = false
                runTask = nil
                return
            }
        }

        await completeSetup()
    }

    private func completeSetup() async {
        stage = .finalizing
        isRunning = false
        isComplete = true
        runTask = nil
        await onReady()
    }

    private func apply(records: [ToolDependencyRecord]) {
        for record in records {
            updateStatus(record.status, for: record.descriptor.id)
        }
    }

    private func updateStatus(_ status: ToolDependencyStatus, for dependencyID: ToolDependencyID) {
        guard let index = dependencies.firstIndex(where: { $0.id == dependencyID }) else {
            return
        }

        dependencies[index] = ToolDependencyRecord(
            descriptor: dependencies[index].descriptor,
            status: status
        )
    }
}
