import Foundation

struct PlaceholderJobStatus: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let stage: String
}

@MainActor
final class BatchViewModel: ObservableObject {
    @Published var overviewText = "The processing pipeline will land in Phases 5 through 11."
    @Published var jobs: [PlaceholderJobStatus] = [
        PlaceholderJobStatus(fileName: "interview_001.m4a", stage: "Pending"),
        PlaceholderJobStatus(fileName: "meeting_002.mp3", stage: "Pending"),
        PlaceholderJobStatus(fileName: "note_003.wav", stage: "Pending"),
    ]
}
