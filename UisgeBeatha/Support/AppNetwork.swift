import Foundation

/// Shared configuration for every outbound request the app makes.
///
/// `URLSession.shared` waits 60 seconds per request before giving up, and the
/// barcode cascade runs two tiers back to back, so a flaky connection could
/// leave the person staring at "Looking up…" for two minutes. Every lookup
/// here is best-effort with a manual fallback, so failing fast is the right
/// tradeoff.
nonisolated enum AppNetwork {
    /// One identifier for every API. Open Food Facts and Wikimedia both ask
    /// clients to identify themselves, and Wikimedia started enforcing rate
    /// limits by client in 2026. Swap the URL for a support page or contact
    /// address before an App Store release.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "UisgeBeatha/\(version) (iOS; +https://github.com/ryopang/uisgebeatha)"
    }()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()

    /// `AsyncImage` loads through `URLSession.shared`, whose default cache is
    /// too small to hold stock photos between launches, so rows re-download
    /// them. Call once at launch.
    static func configureSharedImageCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024
        )
    }
}
