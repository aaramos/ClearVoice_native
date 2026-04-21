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
            "Results"
        }
    }

    var description: String {
        switch self {
        case .importing:
            "Drop a source folder and review the files that are ready to process."
        case .configuring:
            "Choose the enhancement method and set concurrency for the batch."
        case .processing:
            "Track the batch run without changing the underlying settings."
        case .review:
            "Open a browser-based results page for the completed batch and share the output more easily."
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
