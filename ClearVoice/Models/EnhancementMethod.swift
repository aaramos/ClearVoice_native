import Foundation

enum EnhancementMethod: String, CaseIterable, Equatable, Sendable, Identifiable {
    case dfn = "DFN"
    case hybrid = "HYBRID"

    var id: String { rawValue }

    var outputSuffix: String { rawValue }

    var title: String {
        switch self {
        case .dfn:
            return "DFN"
        case .hybrid:
            return "Hybrid"
        }
    }

    var detail: String {
        switch self {
        case .dfn:
            return "DeepFilterNet enhancement with lighter overall shaping."
        case .hybrid:
            return "FFmpeg cleanup plus DeepFilterNet with stronger noise reduction."
        }
    }
}
