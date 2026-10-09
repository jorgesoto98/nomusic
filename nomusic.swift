import Cocoa

let musicID = "com.apple.Music"
let spotifyID = "com.spotify.client"
let debounceInterval: CFAbsoluteTime = 3

// Top-level `let`s in main.swift initialize eagerly; `lazy` defers loading the
// AppleScript component until Spotify actually has to play.
final class Spotify {
    static let shared = Spotify()
    private lazy var playScript: NSAppleScript? = {
        let s = NSAppleScript(source: "tell application id \"\(spotifyID)\" to play")
        s?.compileAndReturnError(nil)
        return s
    }()

    func play(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.playScript?.executeAndReturnError(nil)
        }
    }
}

var lastReplaceTime: CFAbsoluteTime = 0
// Set only when NoMusic launches Spotify, so opening Spotify by hand doesn't auto-play.
var playWhenSpotifyLaunches = false

func isRunning(_ bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

func launchSpotifyAndPlay() {
    guard !isRunning(spotifyID) else {
        Spotify.shared.play(after: 0.5)
        return
    }
    // Resolve by bundle ID so Spotify works from ~/Applications or any other path.
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyID) else { return }
    playWhenSpotifyLaunches = true
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        if error != nil { DispatchQueue.main.async { playWhenSpotifyLaunches = false } }
    }
}

// Kills Music and opens Spotify, at most once per debounce window.
// Music is always killed; only the Spotify part is debounced.
func replace(_ musicApps: [NSRunningApplication]) {
    guard !musicApps.isEmpty else { return }
    musicApps.forEach { $0.forceTerminate() }

    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastReplaceTime > debounceInterval else { return }
    lastReplaceTime = now
    launchSpotifyAndPlay()
}

func replaceRunningMusic() {
    replace(NSRunningApplication.runningApplications(withBundleIdentifier: musicID))
}

func launchedApp(_ notification: Notification) -> NSRunningApplication? {
    notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
}

let center = NSWorkspace.shared.notificationCenter

replaceRunningMusic()

// Stored as globals so they live for the process lifetime
let _obs1: Any = center.addObserver(
    forName: NSWorkspace.willLaunchApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = launchedApp(notification), app.bundleIdentifier == musicID else { return }
    replace([app])
}

let _obs2: Any = center.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard playWhenSpotifyLaunches,
          let app = launchedApp(notification), app.bundleIdentifier == spotifyID else { return }
    playWhenSpotifyLaunches = false
    Spotify.shared.play(after: 1)
}

let _obs3: Any = center.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { _ in
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { replaceRunningMusic() }
}

RunLoop.main.run()
