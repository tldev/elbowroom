import Foundation
import AVFoundation

/// Sound. Five sounds (pebble, whoomp, whoosh, tuck, heads-up), organic and
/// quiet, honoring the master toggle. Coalescing: max one sound per 800 ms;
/// errors are always silent by construction (no error sound exists).
public enum ElbowroomSound: String, CaseIterable {
    case pebble, whoomp, whoosh, tuck, headsUp = "heads-up"
}

public final class SoundPlayer {
    public static let shared = SoundPlayer()
    private var players: [ElbowroomSound: AVAudioPlayer] = [:]
    private var lastPlayed = Date.distantPast

    /// Sounds ship as wav or mp3; both the subdirectory and flattened
    /// lookups run because .process can flatten.
    static func resourceURL(_ sound: ElbowroomSound) -> URL? {
        for ext in ["wav", "mp3"] {
            if let url = AppResources.bundle.url(forResource: "Sounds/\(sound.rawValue)", withExtension: ext)
                ?? AppResources.bundle.url(forResource: sound.rawValue, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    init() {
        for sound in ElbowroomSound.allCases {
            if let url = Self.resourceURL(sound) {
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
