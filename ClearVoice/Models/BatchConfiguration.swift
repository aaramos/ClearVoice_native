import Foundation

struct BatchConfiguration: Equatable, Sendable {
    let sourceFolder: URL
    let outputFolder: URL
    let enhancementMethod: EnhancementMethod
    let maxConcurrency: Int
    let recursiveScan: Bool
    let preserveChannels: Bool
}
