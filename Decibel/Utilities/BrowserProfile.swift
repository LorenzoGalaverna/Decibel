// Decibel/Utilities/BrowserProfile.swift
import Foundation

/// Reads the Chromium profile a browser process was launched with.
///
/// Chromium browsers mix the audio of every tab inside a single audio service
/// process before handing it to Core Audio, so macOS cannot separate tabs. A
/// second instance launched with its own `--user-data-dir` does run its own
/// audio service, which Core Audio reports as a distinct process — that is the
/// only way to get independent volume for two pages on macOS.
///
/// Those instances share a bundle identifier, so without something to tell them
/// apart they also share their persisted volume and mute settings, and muting
/// one mutes the other. This supplies that distinguishing key.
enum BrowserProfile {
    private static let flag = "--user-data-dir="

    /// The `--user-data-dir` a process was launched with, or nil when it runs
    /// the browser's default profile.
    static func userDataDirectory(forPID pid: pid_t) -> String? {
        for argument in arguments(forPID: pid) where argument.hasPrefix(flag) {
            let path = String(argument.dropFirst(flag.count))
            return path.isEmpty ? nil : path
        }
        return nil
    }

    /// A short label for the profile, suitable for telling two instances apart
    /// in the UI. Nil for the default profile, which needs no qualifier.
    static func label(forPID pid: pid_t) -> String? {
        guard let dir = userDataDirectory(forPID: pid) else { return nil }
        return (dir as NSString).lastPathComponent
    }

    /// Reads another process's argument vector via sysctl. Works without extra
    /// privileges for processes owned by the same user, which is all we need;
    /// returns an empty array rather than failing when it cannot be read.
    private static func arguments(forPID pid: pid_t) -> [String] {
        var argMaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var argMaxSize = MemoryLayout<Int32>.size
        guard sysctl(&argMaxMIB, 2, &argMax, &argMaxSize, nil, 0) == 0, argMax > 0 else {
            return []
        }

        var buffer = [CChar](repeating: 0, count: Int(argMax))
        var argsMIB: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = Int(argMax)
        guard sysctl(&argsMIB, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return []
        }

        var count: Int32 = 0
        _ = withUnsafeMutableBytes(of: &count) { dest in
            buffer.withUnsafeBytes { src in
                dest.copyBytes(from: UnsafeRawBufferPointer(rebasing: src[0..<4]))
            }
        }
        guard count > 0 else { return [] }

        // Layout: argc, the executable path, padding NULs, then argc C strings.
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var result: [String] = []
        var bytes: [UInt8] = []
        while index < size, result.count < Int(count) {
            let byte = UInt8(bitPattern: buffer[index])
            if byte == 0 {
                result.append(String(decoding: bytes, as: UTF8.self))
                bytes.removeAll(keepingCapacity: true)
            } else {
                bytes.append(byte)
            }
            index += 1
        }
        return result
    }
}
