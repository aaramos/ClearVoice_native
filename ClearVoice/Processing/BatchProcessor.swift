import Foundation

actor BatchProcessor {
    private let config: BatchConfiguration
    private let resolver: OutputPathResolver
    private let services: ServiceBundle
    private var stopAfterCurrent = false

    init(
        config: BatchConfiguration,
        resolver: OutputPathResolver,
        services: ServiceBundle
    ) {
        self.config = config
        self.resolver = resolver
        self.services = services
    }

    func requestStopAfterCurrent() {
        stopAfterCurrent = true
    }

    func run(
        files: [AudioFileItem],
        update: @escaping @Sendable (AudioFileItem) async -> Void
    ) async {
        let semaphore = AsyncSemaphore(value: config.maxConcurrency)
        let fileJob = FileJob(config: config, resolver: resolver, services: services)

        await withTaskGroup(of: Void.self) { group in
            for file in files {
                if stopAfterCurrent {
                    break
                }

                await semaphore.acquire()

                if stopAfterCurrent {
                    await semaphore.release()
                    break
                }

                group.addTask {
                    await fileJob.run(item: file, update: update)
                    await semaphore.release()
                }
            }

            await group.waitForAll()
        }
    }
}
