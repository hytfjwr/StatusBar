import AppKit
import Foundation
import OSLog
import StatusBarKit

private let logger = Logger(subsystem: "com.statusbar", category: "SpotifyService")

@MainActor
@Observable
final class SpotifyService {
    var isPlaying = false
    var trackName = ""
    var artistName = ""
    var albumName = ""
    var artworkURL: URL?
    var duration: Double = 0
    var position: Double = 0
    var isShuffling = false
    var isRepeating = false

    private var observer: NSObjectProtocol?
    private var positionTimer: Timer?
    private var isFetchingPosition = false

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            let state = info?["Player State"] as? String ?? ""
            let name = info?["Name"] as? String ?? ""
            let artist = info?["Artist"] as? String ?? ""
            let album = info?["Album"] as? String ?? ""
            let duration = info?["Duration"] as? Double ?? 0
            Task { @MainActor in
                self?.handlePlaybackChange(
                    state: state, name: name, artist: artist,
                    album: album, duration: duration
                )
            }
        }
        fetchTrackInfo()
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func handlePlaybackChange(
        state: String, name: String, artist: String,
        album: String, duration: Double
    ) {
        isPlaying = (state == "Playing")

        if isPlaying {
            trackName = truncate(name, maxLength: 24)
            artistName = truncate(artist, maxLength: 35)
            albumName = truncate(album, maxLength: 35)
            self.duration = duration / 1_000.0
            fetchArtworkURL()
        }
    }

    func fetchTrackInfo() {
        Task {
            do {
                let script = """
                tell application "Spotify"
                    if player state is playing then
                        set trackName to name of current track
                        set trackArtist to artist of current track
                        set trackAlbum to album of current track
                        set trackDuration to duration of current track
                        set artURL to artwork url of current track
                        set playerPos to player position
                        set isShuffle to shuffling
                        set isRepeat to repeating
                        return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackDuration & "|||" & artURL & "|||" & playerPos & "|||" & isShuffle & "|||" & isRepeat
                    else
                        return "NOT_PLAYING"
                    end if
                end tell
                """
                let result = try await ShellCommand.run("osascript", arguments: ["-e", script])
                if result == "NOT_PLAYING" {
                    isPlaying = false
                    return
                }
                let parts = result.components(separatedBy: "|||")
                guard parts.count >= 6 else {
                    return
                }
                isPlaying = true
                trackName = truncate(parts[0], maxLength: 24)
                artistName = truncate(parts[1], maxLength: 35)
                albumName = truncate(parts[2], maxLength: 35)
                duration = (Double(parts[3]) ?? 0) / 1_000.0
                artworkURL = URL(string: parts[4])
                position = Double(parts[5]) ?? 0
                if parts.count >= 8 {
                    isShuffling = parts[6].trimmingCharacters(in: .whitespaces) == "true"
                    isRepeating = parts[7].trimmingCharacters(in: .whitespaces) == "true"
                }
            } catch {
                logger.debug("fetchTrackInfo failed: \(error.localizedDescription)")
                isPlaying = false
            }
        }
    }

    private func fetchArtworkURL() {
        Task {
            do {
                let result = try await ShellCommand
                    .run("osascript", arguments: ["-e", "tell application \"Spotify\" to get artwork url of current track"])
                artworkURL = URL(string: result)
            } catch {
                logger.debug("fetchArtworkURL failed: \(error.localizedDescription)")
            }
        }
    }

    func startPositionPolling() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchPosition()
            }
        }
    }

    func stopPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func fetchPosition() {
        guard !isFetchingPosition else { return }
        isFetchingPosition = true
        Task {
            defer { isFetchingPosition = false }
            do {
                let result = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to get player position"])
                position = Double(result) ?? position
            } catch {
                logger.debug("fetchPosition failed: \(error.localizedDescription)")
            }
        }
    }

    func playPause() {
        Task {
            do {
                _ = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to playpause"])
            } catch {
                logger.debug("playPause failed: \(error.localizedDescription)")
            }
        }
    }

    func nextTrack() {
        Task {
            do {
                _ = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to play next track"])
            } catch {
                logger.debug("nextTrack failed: \(error.localizedDescription)")
            }
        }
    }

    func previousTrack() {
        Task {
            do {
                _ = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to play previous track"])
            } catch {
                logger.debug("previousTrack failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleShuffle() {
        isShuffling.toggle()
        Task {
            do {
                _ = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to set shuffling to not shuffling"])
            } catch {
                logger.debug("toggleShuffle failed: \(error.localizedDescription)")
            }
        }
    }

    private var seekTask: Task<Void, Never>?

    func seekTo(position: Double) {
        self.position = position
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let pos = Int(position)
            do {
                _ = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to set player position to \(pos)"])
            } catch {
                logger.debug("seekTo failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleRepeat() {
        isRepeating.toggle()
        Task {
            do {
                _ = try await ShellCommand.run("osascript", arguments: ["-e", "tell application \"Spotify\" to set repeating to not repeating"])
            } catch {
                logger.debug("toggleRepeat failed: \(error.localizedDescription)")
            }
        }
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        let truncated = String(text.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
}
