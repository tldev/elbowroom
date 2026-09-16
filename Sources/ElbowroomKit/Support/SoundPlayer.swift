import Foundation
import AVFoundation

/// Sound. Five sounds (pebble, whoomp, pour, tuck, heads-up), organic and
/// quiet, honoring the master toggle. Coalescing: max one sound per 800 ms;
/// errors are always silent by construction (no error sound exists).
public enum ElbowroomSound: String, CaseIterable {
    case pebble, whoomp, pour, tuck, headsUp = "heads-up"
}

public final class SoundPlayer {
    public static let shared = SoundPlayer()
    private var players: [ElbowroomSound: AVAudioPlayer] = [:]
    private var lastPlayed = Date.distantPast

    init() {
        for sound in ElbowroomSound.allCases {
            if let url = Bundle.module.url(forResource: "Sounds/\(sound.rawValue)", withExtension: "wav")
                ?? Bundle.module.url(forResource: sound.rawValue, withExtension: "wav") {
                players[sound] = try? AVAudioPlayer(contentsOf: url)
                players[sound]?.volume = 0.5
                players[sound]?.prepareToPlay()
            }
        }
    }

    public func play(_ sound: ElbowroomSound) {
        guard SettingsStore.shared.soundsOn else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) > 0.8 else { return }
        lastPlayed = now
        players[sound]?.currentTime = 0
        players[sound]?.play()
    }
}
