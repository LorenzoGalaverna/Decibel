// DecibelTests/TargetAppResolverTests.swift
import Testing
import Foundation
import AppKit
@testable import Decibel

@Suite("TargetAppResolver")
@MainActor
struct TargetAppResolverTests {
    private static let ownBundleID = "com.decibelapp.Decibel"

    // MARK: - No-audible fallback (Phase 1 behavior preserved)

    @Test("resolveTargetBundleID returns nil when nothing has activated and Decibel is frontmost")
    func coldLaunchReturnsNil() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { Self.ownBundleID }
        )
        #expect(resolver.resolveTargetBundleID(audibleCandidates: []) == nil)
    }

    @Test("resolveTargetBundleID returns frontmost when not Decibel and no candidates")
    func returnsFrontmostWhenNotDecibel() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Safari" }
        )
        #expect(resolver.resolveTargetBundleID(audibleCandidates: []) == "com.apple.Safari")
    }

    @Test("resolveTargetBundleID falls back to last cached non-Decibel ID when Decibel is frontmost")
    func decibelFrontmostUsesCachedFallback() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { Self.ownBundleID }
        )
        resolver.handleActivation(bundleID: "com.apple.Safari")

        #expect(resolver.resolveTargetBundleID(audibleCandidates: []) == "com.apple.Safari")
    }

    @Test("activation by Decibel does not overwrite the cached fallback")
    func decibelActivationDoesNotPoisonCache() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { Self.ownBundleID }
        )
        resolver.handleActivation(bundleID: "com.apple.Safari")
        resolver.handleActivation(bundleID: Self.ownBundleID)

        #expect(resolver.resolveTargetBundleID(audibleCandidates: []) == "com.apple.Safari")
    }

    // MARK: - Audible-source resolution (Rule F)

    @Test("returns the sole audible candidate when only one is audible")
    func singleAudibleCandidate() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        let target = resolver.resolveTargetBundleID(audibleCandidates: ["com.spotify.client"])
        #expect(target == "com.spotify.client")
    }

    @Test("prefers frontmost when frontmost is in the audible set")
    func frontmostInCandidatesWins() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Safari" }
        )
        let target = resolver.resolveTargetBundleID(
            audibleCandidates: ["com.spotify.client", "com.apple.Safari"]
        )
        #expect(target == "com.apple.Safari")
    }

    @Test("reuses lastTargetedBundleID when frontmost is not audible")
    func stickyLastTargetWhenFrontmostNotAudible() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        _ = resolver.resolveTargetBundleID(audibleCandidates: ["com.spotify.client"])
        let target = resolver.resolveTargetBundleID(
            audibleCandidates: ["com.spotify.client", "com.apple.Safari"]
        )
        #expect(target == "com.spotify.client")
    }

    @Test("falls back to first candidate when neither frontmost nor sticky is audible")
    func fallbackToFirstCandidate() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        let target = resolver.resolveTargetBundleID(
            audibleCandidates: ["com.spotify.client", "com.apple.Safari"]
        )
        #expect(target == "com.spotify.client")
    }

    @Test("filters out blocklisted system daemons")
    func blocklistFiltersSystemDaemons() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        let target = resolver.resolveTargetBundleID(
            audibleCandidates: ["com.apple.systemsoundserverd", "com.spotify.client"]
        )
        #expect(target == "com.spotify.client")
    }

    @Test("falls back to frontmost path when only blocklisted daemons are audible")
    func allBlocklistedFallsBackToFrontmost() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        let target = resolver.resolveTargetBundleID(
            audibleCandidates: ["com.apple.systemsoundserverd", "com.apple.coreaudiod"]
        )
        #expect(target == "com.apple.Notes")
    }

    @Test("sticky lastTargetedBundleID breaks when target stops being audible")
    func stickyBreaksWhenTargetQuits() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        _ = resolver.resolveTargetBundleID(audibleCandidates: ["com.spotify.client"])
        let second = resolver.resolveTargetBundleID(
            audibleCandidates: ["com.spotify.client", "com.apple.Safari"]
        )
        #expect(second == "com.spotify.client")
        let third = resolver.resolveTargetBundleID(audibleCandidates: ["com.apple.Safari"])
        #expect(third == "com.apple.Safari")
    }

    @Test("filters Decibel's own bundle ID out of candidates")
    func ownBundleIDFilteredFromCandidates() {
        let resolver = TargetAppResolver(
            ownBundleID: Self.ownBundleID,
            frontmostBundleIDProvider: { "com.apple.Notes" }
        )
        let target = resolver.resolveTargetBundleID(
            audibleCandidates: [Self.ownBundleID, "com.spotify.client"]
        )
        #expect(target == "com.spotify.client")
    }
}
