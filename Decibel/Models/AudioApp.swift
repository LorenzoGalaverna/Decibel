// Decibel/Models/AudioApp.swift
import AppKit
import AudioToolbox

struct AudioApp: Identifiable, Hashable {
    let id: pid_t
    let processObjectIDs: [AudioObjectID]
    let name: String
    let icon: NSImage
    let bundleID: String?
    let isHelperBacked: Bool

    /// The `--user-data-dir` of a Chromium browser running a non-default
    /// profile. Two such instances are separate processes with separate audio,
    /// but share a bundle identifier, so this is what keeps their settings and
    /// their rows apart. Nil for everything else.
    let profileDirectory: String?

    init(
        id: pid_t,
        processObjectIDs: [AudioObjectID],
        name: String,
        icon: NSImage,
        bundleID: String?,
        isHelperBacked: Bool = false,
        profileDirectory: String? = nil
    ) {
        self.id = id
        self.processObjectIDs = processObjectIDs
        self.name = name
        self.icon = icon
        self.bundleID = bundleID
        self.isHelperBacked = isHelperBacked
        self.profileDirectory = profileDirectory
    }

    /// Key under which this app's volume, mute and boost are stored.
    ///
    /// Qualified by the browser profile when there is one, so a second browser
    /// instance keeps its own settings instead of inheriting the first one's —
    /// without it, muting one window mutes every window of that browser. Apps
    /// on the default profile keep the bare bundle identifier, so settings
    /// saved by earlier versions still load.
    var persistenceIdentifier: String {
        guard let bundleID else { return "name:\(name)" }
        guard let profileDirectory else { return bundleID }
        return "\(bundleID)#\(profileDirectory)"
    }

    /// Name shown in the app list, qualified when several instances of the same
    /// browser are running so they can be told apart.
    var displayName: String {
        guard let profileDirectory else { return name }
        let profile = (profileDirectory as NSString).lastPathComponent
        return profile.isEmpty ? name : "\(name) (\(profile))"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id
    }
}
