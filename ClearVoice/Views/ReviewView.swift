import SwiftUI

struct ReviewView: View {
    let onStartNewBatch: () -> Void

    var body: some View {
        StepCard(
            title: "Review",
            detail: "This placeholder proves the post-processing route exists before transcript rendering and Finder actions arrive in Phase 12."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review content will land after the pipeline is in place.")
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Spacer()
                    Button("New Batch", action: onStartNewBatch)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
