import AVFoundation
import SwiftUI

struct AudioPreviewPlayerView: View {
    let fileURL: URL

    @StateObject private var model: AudioPreviewPlayerModel

    init(fileURL: URL) {
        self.fileURL = fileURL
        _model = StateObject(wrappedValue: AudioPreviewPlayerModel(fileURL: fileURL))
    }

    var body: some View {
        HStack(spacing: 12) {
            controlButton(systemName: "gobackward.10", action: model.skipBackward)
            controlButton(systemName: model.isPlaying ? "pause.fill" : "play.fill", action: model.togglePlayback)
            controlButton(systemName: "goforward.10", action: model.skipForward)

            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.duration, 1)
            )
            .tint(.orange)

            Text(model.timeLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

@MainActor
private final class AudioPreviewPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 1

    private let fileURL: URL
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
        loadPlayer()
    }

    deinit {
        timer?.invalidate()
    }

    var timeLabel: String {
        "\(Self.timeString(from: currentTime)) / \(Self.timeString(from: duration))"
    }

    func togglePlayback() {
        guard let audioPlayer else {
            loadPlayer()
            return
        }

        if audioPlayer.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func skipBackward() {
        seek(to: max(currentTime - 10, 0))
    }

    func skipForward() {
        seek(to: min(currentTime + 10, duration))
    }

    func seek(to value: TimeInterval) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = value
        currentTime = value
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        pause()
        currentTime = duration
    }

    private func loadPlayer() {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            duration = max(player.duration, 1)
            currentTime = player.currentTime
        } catch {
            audioPlayer = nil
            duration = 1
            currentTime = 0
        }
    }

    private func play() {
        guard let audioPlayer else { return }
        audioPlayer.play()
        isPlaying = true
        startTimer()
    }

    private func pause() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let audioPlayer = self.audioPlayer else { return }
            Task { @MainActor in
                self.currentTime = audioPlayer.currentTime
                if !audioPlayer.isPlaying {
                    self.pause()
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private static func timeString(from interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
