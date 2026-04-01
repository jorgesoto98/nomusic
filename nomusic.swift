import Cocoa

let musicID = "com.apple.Music"
let spotifyID = "com.spotify.client"
let spotifyScript: NSAppleScript = {
    let s = NSAppleScript(source: "tell application \"Spotify\" to play")!
    s.compileAndReturnError(nil)
    return s
}()

var lastReplaceTime: CFAbsoluteTime = 0

func killMusic(_ app: NSRunningApplication) {
    app.forceTerminate()
}

func launchSpotifyIfNeeded() {
    if NSRunningApplication.runningApplications(withBundleIdentifier: spotifyID).isEmpty {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Spotify.app"))
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            spotifyScript.executeAndReturnError(nil)
        }
    }
}

func replaceMusic() {
    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastReplaceTime > 3 else { return }
    lastReplaceTime = now

    let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: musicID)
    guard !musicApps.isEmpty else { return }
    musicApps.forEach { killMusic($0) }
    launchSpotifyIfNeeded()
}

let center = NSWorkspace.shared.notificationCenter

replaceMusic()

// Stored as globals so they live for the process lifetime
let _obs1: Any = center.addObserver(
    forName: NSWorkspace.willLaunchApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
              as? NSRunningApplication,
          app.bundleIdentifier == musicID else { return }
    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastReplaceTime > 3 else {
        killMusic(app)
        return
    }
    lastReplaceTime = now
    killMusic(app)
    launchSpotifyIfNeeded()
}

let _obs2: Any = center.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
              as? NSRunningApplication,
          app.bundleIdentifier == spotifyID else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        spotifyScript.executeAndReturnError(nil)
    }
}

let _obs3: Any = center.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { _ in
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { replaceMusic() }
}

RunLoop.main.run()
