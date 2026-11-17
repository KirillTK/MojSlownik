import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class SupabaseClientProviderTests: XCTestCase {
    private static let defaultsSuite = "SupabaseClientProviderTests"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: Self.defaultsSuite)
        super.tearDown()
    }

    private func assertRejects(url: String = "https://x.supabase.co", key: String = "sb_publishable_abc",
                               _ expected: SupabaseConfiguration.ValidationError,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SupabaseConfiguration(urlString: url, publishableKey: key),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? SupabaseConfiguration.ValidationError, expected, file: file, line: line)
        }
    }

    // MARK: Configuration

    func testProductionConfigurationPointsAtProjectOverHTTPS() {
        let url = SupabaseConfiguration.production.url
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(percentEncoded: false), "bjwptrfbtcmxlhjaxiip.supabase.co")
    }

    func testProductionKeyIsPublishable() {
        let key = SupabaseConfiguration.production.publishableKey
        XCTAssertTrue(key.hasPrefix("sb_publishable_"))
        XCTAssertFalse(key.contains("sb_secret_"))
    }

    func testAcceptsValidConfigurationAndTrimsKey() throws {
        let configuration = try SupabaseConfiguration(urlString: "https://x.supabase.co",
                                                      publishableKey: "  sb_publishable_abc\n")
        XCTAssertEqual(configuration.publishableKey, "sb_publishable_abc")
    }

    func testRejectsNonHTTPSURL() { assertRejects(url: "http://x.supabase.co", .invalidURL) }
    func testRejectsURLWithoutHost() { assertRejects(url: "https://", .invalidURL) }
    func testRejectsMalformedURL() { assertRejects(url: "", .invalidURL) }

    func testRejectsSecretKey() { assertRejects(key: "sb_secret_abc", .invalidKey) }
    func testRejectsEmptyKey() { assertRejects(key: "  ", .invalidKey) }
    func testRejectsBarePrefixKey() { assertRejects(key: "sb_publishable_", .invalidKey) }
    /// Legacy anon JWTs are public too, but the app pins the new publishable key format.
    func testRejectsLegacyJWTKey() { assertRejects(key: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.x", .invalidKey) }

    // MARK: Provider

    func testProviderIsLazy() {
        let provider = SupabaseClientProvider()
        XCTAssertFalse(provider.isClientCreated)
        XCTAssertEqual(provider.configuration, .production)
    }

    func testClientIsCreatedOnceAndReused() {
        let provider = SupabaseClientProvider()
        let first = provider.client
        XCTAssertTrue(provider.isClientCreated)
        XCTAssertTrue(first === provider.client)
    }

    func testAppResourcesDoesNotCreateSupabaseClient() throws {
        let resources = try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                                         defaults: UserDefaults(suiteName: Self.defaultsSuite)!)
        XCTAssertFalse(resources.supabase.isClientCreated)
    }

    #if DEBUG
    func testUITestResourcesDoNotCreateSupabaseClient() throws {
        let resources = try AppResources.uiTest(UITestLaunchConfiguration(fixture: .empty, prefill: nil))
        XCTAssertFalse(resources.supabase.isClientCreated)
        UserDefaults().removePersistentDomain(forName: UITestLaunchConfiguration.defaultsSuite)
    }
    #endif
}
