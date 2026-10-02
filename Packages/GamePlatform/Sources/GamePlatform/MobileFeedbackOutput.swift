#if os(iOS)
import AVFAudio
import CoreHaptics
import Foundation
import UIKit

@MainActor
final class MobileFeedbackOutput: ShellFeedbackOutput {
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let session = AVAudioSession.sharedInstance()
    private var sounds: [ShellFeedbackCue: AVAudioPlayer] = [:]
    private var music: AVAudioPlayer?
    private var sessionActive = false

    deinit {
        // The session is shared by the process, so releasing players alone does
        // not release an activation owned by this shell's output adapter.
        sounds.values.forEach { $0.stop() }
        music?.stop()
        if sessionActive {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func playSound(_ cue: ShellFeedbackCue) {
        guard activateAudio() else { return }
        do {
            let player: AVAudioPlayer
            if let existing = sounds[cue] {
                player = existing
            } else {
                player = try AVAudioPlayer(data: AuthoredAudio.cue(cue))
                player.volume = 0.6
                sounds[cue] = player
            }
            player.currentTime = 0
            player.play()
        } catch {
            // Optional output failing must not affect the title's game rules.
            sounds[cue] = nil
        }
    }

    func playHaptic(_ cue: ShellFeedbackCue) {
        guard supportsHaptics else { return }
        switch cue {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func setMusicPlaying(_ playing: Bool) {
        guard playing else {
            music?.stop()
            deactivateIfIdle()
            return
        }
        guard music?.isPlaying != true, activateAudio() else { return }
        do {
            if music == nil {
                music = try AVAudioPlayer(data: AuthoredAudio.music())
                music?.numberOfLoops = -1
                music?.volume = 0.35
            }
            music?.play()
        } catch {
            music = nil
        }
    }

    func stopSounds() {
        sounds.values.forEach { $0.stop() }
        deactivateIfIdle()
    }

    func stopAll() {
        sounds.values.forEach { $0.stop() }
        music?.stop()
        deactivateIfIdle()
    }

    func resetAudio() {
        stopAll()
        sounds.removeAll()
        music = nil
        sessionActive = false
    }

    func recoverAudioSession() -> Bool {
        sessionActive = false
        return activateAudio()
    }

    private func activateAudio() -> Bool {
        guard !sessionActive else { return true }
        do {
            // Ambient respects the device's silent switch and mixes other audio.
            // No recording category, background mode, or permission is requested.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            sessionActive = true
            return true
        } catch {
            return false
        }
    }

    private func deactivateIfIdle() {
        guard sessionActive, music?.isPlaying != true,
              !sounds.values.contains(where: \.isPlaying) else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }
}

@MainActor
func makeMobileAudioObserver() -> NotificationAudioObserver {
    // These notifications support the iOS 18 minimum and pinned Xcode 26.6.
    // Xcode 27 introduces newer notification APIs; migration belongs with a
    // deployment/toolchain update rather than dropping the supported floor.
    NotificationAudioObserver(
        center: .default,
        names: [AVAudioSession.interruptionNotification,
                AVAudioSession.routeChangeNotification,
                AVAudioSession.mediaServicesWereResetNotification]
    ) { notification in
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return nil }
            if type == .began { return .interruptionBegan }
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            return .interruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
        case AVAudioSession.routeChangeNotification:
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            return reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue ? .routeDisconnected : nil
        case AVAudioSession.mediaServicesWereResetNotification:
            return .mediaServicesReset
        default:
            return nil
        }
    }
}
#endif
