// Decibel/Utilities/BrowserChannels.swift
import AppKit
import Foundation
import os

/// Launches Chromium browser instances that macOS can control independently.
///
/// A Chromium browser mixes every tab and every signed-in profile into one
/// audio service process before Core Audio ever sees it, so switching Chrome
/// users does not give you a second volume slider — all of them share one.
/// What does get its own audio service, and therefore its own row here, is an
/// instance started with a separate `--user-data-dir`.
///
/// Channels are directories kept under Application Support, so they persist:
/// sign in once in a channel and it stays signed in the next time it opens.
@MainActor
enum BrowserChannels {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Decibel", category: "BrowserChannels")

    /// Chromium browsers that honour `--user-data-dir`, most preferred first.
    private static let supportedBundleIDs = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.chromium.Chromium",
    ]

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Decibel/BrowserChannels", isDirectory: true)
    }

    /// Whether any supported browser is installed; the UI hides the control otherwise.
    static var isAvailable: Bool { browserURL() != nil }

    static func browserURL() -> URL? {
        for id in supportedBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        return nil
    }

    /// Channel directories created so far, in creation order.
    static func existingChannels() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Opens a channel: reuses the first one that is not already running, so a
    /// channel's sign-ins and tabs come back, and only creates a new directory
    /// when every existing channel is in use.
    @discardableResult
    static func openChannel() -> URL? {
        guard let browser = browserURL() else {
            logger.error("No Chromium browser installed; cannot open an audio channel")
            return nil
        }

        let running = runningUserDataDirectories()
        let target = existingChannels().first { !running.contains($0.standardizedFileURL.path) }
            ?? nextChannelURL()

        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create channel directory: \(error.localizedDescription)")
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        // Without this the request is handed to the running browser, which just
        // opens a window in the existing instance and shares its audio service.
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--user-data-dir=\(target.standardizedFileURL.path)",
            "--no-first-run",
            "--no-default-browser-check",
        ]

        NSWorkspace.shared.openApplication(at: browser, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not open audio channel: \(error.localizedDescription)")
            }
        }
        return target
    }

    private static func nextChannelURL() -> URL {
        let used = Set(existingChannels().map(\.lastPathComponent))
        var index = 1
        while used.contains("Channel \(index)") { index += 1 }
        return root.appendingPathComponent("Channel \(index)", isDirectory: true)
    }

    /// Profile directories of browser instances running right now, used to tell
    /// which channels are already open.
    private static func runningUserDataDirectories() -> Set<String> {
        var result: Set<String> = []
        for app in NSWorkspace.shared.runningApplications
        where supportedBundleIDs.contains(app.bundleIdentifier ?? "") {
            if let dir = BrowserProfile.userDataDirectory(forPID: app.processIdentifier) {
                result.insert((dir as NSString).standardizingPath)
            }
        }
        return result
    }
}
