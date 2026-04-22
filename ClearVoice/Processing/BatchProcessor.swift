import Foundation

actor BatchProcessor {
    private let config: BatchConfiguration
    private let resolver: OutputPathResolver
    private let services: ServiceBundle
    private var cancelledFileIDs: Set<UUID> = []
    private var batchCancellationRequested = false
    private var activeTasks: [UUID: Task<AudioFileItem, Never>] = [:]

    init(
        config: BatchConfiguration,
        resolver: OutputPathResolver,
        services: ServiceBundle
    ) {
        self.config = config
        self.resolver = resolver
        self.services = services
    }

    func cancelFile(id: UUID) {
        cancelledFileIDs.insert(id)
        activeTasks[id]?.cancel()
    }

    func cancelAll() {
        batchCancellationRequested = true
        for (id, task) in activeTasks {
            cancelledFileIDs.insert(id)
            task.cancel()
        }
    }

    func run(
        files: [AudioFileItem],
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async {
        let semaphore = AsyncSemaphore(value: config.maxConcurrency)
        let fileJob = FileJob(config: config, resolver: resolver, services: services)
        var launchedTasks: [Task<Void, Never>] = []

        for file in files {
            if await shouldCancel(file.id) {
                await update(cancelledItem(from: file))
                continue
            }

            await semaphore.acquire()

            if await shouldCancel(file.id) {
                await semaphore.release()
                await update(cancelledItem(from: file))
                continue
            }

            let task = Task<AudioFileItem, Never> {
                let result = await fileJob.run(item: file, update: update)
                await semaphore.release()
                await self.finishTask(id: file.id)
                return result
            }

            activeTasks[file.id] = task
            launchedTasks.append(Task {
                _ = await task.value
            })
        }

        for task in launchedTasks {
            _ = await task.value
        }
    }

    private func shouldCancel(_ id: UUID) -> Bool {
        batchCancellationRequested || cancelledFileIDs.contains(id)
    }

    private func finishTask(id: UUID) {
        activeTasks[id] = nil
    }

    private func cancelledItem(from item: AudioFileItem) -> AudioFileItem {
        var item = item
        item.stage = .cancelled
        return item
    }
}
