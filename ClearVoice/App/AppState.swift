enum AppState: Int, CaseIterable, Equatable {
    case importing
    case configuring
    case processing
    case review

    var title: String {
        switch self {
        case .importing:
            "Import"
        case .configuring:
            "Configure"
        case .processing:
            "Process"
        case .review:
            "Review"
        }
    }

    var description: String {
        switch self {
        case .importing:
            "Choose the source and output folders before processing begins."
        case .configuring:
            "Set intensity and languages, then lock the batch configuration."
        case .processing:
            "Track the batch run without changing the underlying settings."
        case .review:
            "Inspect outputs and copy or reveal exported results."
        }
    }

    var stepIndex: Int {
        switch self {
        case .importing:
            1
        case .configuring:
            2
        case .processing:
            3
        case .review:
            4
        }
    }
}
