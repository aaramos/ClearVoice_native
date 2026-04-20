import SwiftUI

struct LaunchFailureView: View {
    let error: LaunchRequirementsError
    let onQuit: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "key.horizontal.fill")
        } description: {
            Text(error.message)
                .multilineTextAlignment(.center)
        } actions: {
            Button("Quit ClearVoice", action: onQuit)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
