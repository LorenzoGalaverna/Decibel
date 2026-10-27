// Decibel/Utilities/BrowserChannels.swift
import AppKit
import Foundation
import os

/// Opens Chromium browser windows that macOS can control the volume of
/// independently.
///
/// A Chromium browser mixes every tab, window and signed-in profile into one
/// audio service process before Core Audio sees any of it, so no amount of
/// work on this side can separate two tabs: by the time the sound reaches
/// macOS the distinction is gone. What does get its own audio service, and so
/// its own row and slider here, is a browser started with a separate
/// `--user-data-dir`. The browser's own interface never does that — every way
/// of opening a window from inside Chrome joins the running instance — so this
/// is the only way to get a second one.
///
/// A fresh directory would mean a signed-out browser, so a channel is cloned
/// from one of the user's existing profiles. On APFS that is a copy-on-write
/// clone: effectively instant and costing almost no disk until files diverge.
/// Channels persist, so a channel reopens with its own tabs and sign-ins.
@MainActor
enum BrowserChannels {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Decibel", category: "BrowserChannels")

    /// A signed-in profile of the installed browser, offered as a starting point.
    struct Profile: Identifiable, Hashable {
        let id: String        // on-disk directory, e.g. "Profile 6"
        let name: String      // e.g. "Innexio"
        let account: String?  // e.g. "innexiosoftware@gmail.com"

        var menuTitle: String {
            guard let account, !account.isEmpty, account != name else { return name }
            return "\(name) — \(account)"
        }
    }

    /// Chromium browsers that honour `--user-data-dir`, most preferred first,
    /// with the Application Support folder each keeps its profiles in.
    private static let supportedBrowsers: [(bundleID: String, supportPath: String)] = [
        ("com.google.Chrome", "Google/Chrome"),
        ("com.brave.Browser", "BraveSoftware/Brave-Browser"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("org.chromium.Chromium", "Chromium"),
    ]

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var channelsRoot: URL {
        applicationSupport.appendingPathComponent("Decibel/BrowserChannels", isDirectory: true)
    }

    /// The installed browser to use, with where its profiles live.
    private static func installedBrowser() -> (url: URL, profiles: URL)? {
        for browser in supportedBrowsers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) {
                return (url, applicationSupport.appendingPathComponent(browser.supportPath, isDirectory: true))
            }
        }
        return nil
    }

    /// Whether to offer this at all; the control stays hidden otherwise.
    static var isAvailable: Bool { installedBrowser() != nil }

    /// The browser's profiles, named as the user named them.
    static func availableProfiles() -> [Profile] {
        guard let browser = installedBrowser() else { return [] }
        let localState = browser.profiles.appendingPathComponent("Local State")

        guard let data = try? Data(contentsOf: localState),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else {
            return []
        }

        return cache.compactMap { directory, value -> Profile? in
            guard let info = value as? [String: Any] else { return nil }
            // Skip profiles whose directory is gone.
            let path = browser.profiles.appendingPathComponent(directory, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            return Profile(
                id: directory,
                name: (info["name"] as? String) ?? directory,
                account: info["user_name"] as? String)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Opens `profile` in a browser instance of its own.
    ///
    /// The first call clones the profile into a channel; later calls reopen
    /// that same channel, so whatever was signed in or left open comes back.
    /// Cloning runs off the main thread because a large profile takes a moment
    /// to walk even when every file is cloned rather than copied.
    static func openChannel(for profile: Profile) {
        guard let browser = installedBrowser() else {
            logger.error("No Chromium browser installed")
            return
        }

        let channel = channelsRoot.appendingPathComponent("Channel-\(profile.id)", isDirectory: true)
        let source = browser.profiles.appendingPathComponent(profile.id, isDirectory: true)
        let destination = channel.appendingPathComponent("Default", isDirectory: true)

        // Already prepared, so reopen it with whatever it had.
        if FileManager.default.fileExists(atPath: destination.path) {
            launch(browser: browser.url, channel: channel)
            return
        }

        let browserURL = browser.url
        Task {
            let cloned = await Task.detached(priority: .userInitiated) {
                clone(from: source, to: destination, channel: channel)
            }.value

            if cloned {
                launch(browser: browserURL, channel: channel)
            } else {
                logger.error("Could not prepare a channel for \(profile.id, privacy: .public)")
            }
        }
    }

    /// Clones a profile directory copy-on-write, falling back to a plain copy
    /// on filesystems that cannot clone.
    private nonisolated static func clone(from source: URL, to destination: URL, channel: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: channel, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let cloned = copyfile(
            source.path, destination.path, nil,
            copyfile_flags_t(COPYFILE_CLONE | COPYFILE_RECURSIVE)) == 0
        if cloned { return true }

        // COPYFILE_CLONE is best-effort; a non-APFS volume needs a real copy.
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    private static func launch(browser: URL, channel: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        // Without this the request is handed to the running browser, which
        // opens a window in the existing instance and shares its audio.
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--user-data-dir=\(channel.standardizedFileURL.path)",
            "--no-first-run",
            "--no-default-browser-check",
        ]
        NSWorkspace.shared.openApplication(at: browser, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not open channel: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
