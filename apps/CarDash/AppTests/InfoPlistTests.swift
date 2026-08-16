import Foundation
import Testing

/// These assertions look trivial and are not.
///
/// A missing usage-description string is not a compile error — it is a hard crash the
/// first time the app touches the corresponding API, on a physical device, which is the
/// one environment this project cannot reach from CI. The same goes for a missing
/// `LSApplicationQueriesSchemes` entry, which makes Spotify authorization fail silently
/// rather than loudly. Checking the built bundle's Info.plist is the cheapest available
/// substitute for running the app.
@Suite("Info.plist")
struct InfoPlistTests {
    enum Failure: Error { case testBundleIsNotHostedByTheApp }

    private func info() throws -> [String: Any] {
        guard let info = Bundle.main.infoDictionary, info["CFBundleIdentifier"] != nil else {
            throw Failure.testBundleIsNotHostedByTheApp
        }
        return info
    }

    @Test("Every privacy usage description the app needs is present and non-empty")
    func usageDescriptions() throws {
        let info = try info()
        for key in [
            "NSLocationWhenInUseUsageDescription",
            "NSAppleMusicUsageDescription",
            "NSMotionUsageDescription"
        ] {
            let value = info[key] as? String
            #expect(value?.isEmpty == false, "\(key) is missing or empty")
        }
    }

    // Contacts is deliberately absent: the app uses CNContactPickerViewController, which
    // requires no authorization, so requesting one would be a permission prompt bought
    // for nothing. If this starts failing because someone reached for CNContactStore,
    // the usage string needs to come back with it.
    @Test("No contacts usage string, because no contacts authorization is requested")
    func noContactsPermission() throws {
        let info = try info()
        #expect(info["NSContactsUsageDescription"] == nil)
    }

    // canOpenURL answers false for any scheme not declared here, whatever the device can
    // actually do. Without these the Phone tile could not tell a phone from an iPad and
    // would disable its own dial button on hardware that dials perfectly well.
    @Test("Dialling and messaging schemes are queryable")
    func telephonySchemes() throws {
        let queries = try #require(try info()["LSApplicationQueriesSchemes"] as? [String])
        #expect(queries.contains("tel"))
        #expect(queries.contains("sms"))
    }

    @Test("Background modes are exactly audio and location")
    func backgroundModes() throws {
        let modes = try #require(try info()["UIBackgroundModes"] as? [String])
        #expect(Set(modes) == ["audio", "location"])
    }

    @Test("iPhone orientations are landscape-only")
    func orientations() throws {
        let orientations = try #require(try info()["UISupportedInterfaceOrientations"] as? [String])
        #expect(Set(orientations) == [
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight"
        ])
    }

    @Test("The Spotify scheme is queryable and our callback scheme is registered")
    func spotifyURLPlumbing() throws {
        let info = try info()
        let queries = try #require(info["LSApplicationQueriesSchemes"] as? [String])
        #expect(queries.contains("spotify"))

        let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("cardash"), "redirect URI cardash://spotify-callback would not resolve")
    }

    // The key must exist even when nobody has registered a Spotify app, because its
    // absence and its emptiness mean different things to `AppConfiguration`: empty is
    // "not configured yet", missing is "the plist entry was lost in a merge".
    @Test("The Spotify client ID key is wired, whether or not it is filled in")
    func spotifyClientID() throws {
        let value = try #require(try info()["SpotifyClientID"] as? String)

        // An unexpanded $(SPOTIFY_CLIENT_ID) would be sent to Spotify verbatim and come
        // back as a generic invalid_client, pointing at the dashboard rather than at the
        // build settings where the fault actually is.
        #expect(!value.contains("$("), "unexpanded build setting: \(value)")
    }

    // Activity.request throws at runtime without this, and nothing in the error names the
    // missing key. It belongs to the app, not to the widget extension that draws the thing.
    @Test("Live Activities are declared by the app")
    func liveActivities() throws {
        let info = try info()
        #expect(info["NSSupportsLiveActivities"] as? Bool == true)
        #expect(
            info["NSSupportsLiveActivitiesFrequentUpdates"] as? Bool == true,
            "without frequent updates the lock screen stops keeping up mid-route"
        )
    }

    // Without the exported type the share sheet has no name or icon for a .cardash file, and
    // without the document type one cannot be opened from Files or AirDrop at all.
    @Test("The layout file type is declared, and the app can open one")
    func layoutFileType() throws {
        let info = try info()
        let identifier = "com.brogwalkerh.cardash.layout"

        let exported = try #require(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try #require(exported.first { $0["UTTypeIdentifier"] as? String == identifier })

        let tags = try #require(declaration["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try #require(tags["public.filename-extension"] as? [String])
        #expect(extensions.contains("cardash"))

        // Conforming to JSON is what lets a layout that has been through email — and had its
        // UTI rewritten to something generic — still open.
        let conforms = declaration["UTTypeConformsTo"] as? [String] ?? []
        #expect(conforms.contains("public.json"))

        let documents = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let handled = documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(handled.contains(identifier))

        // Read where it sits rather than copied into the app's Inbox. Importing reads the
        // bytes and never writes, so copying would only leave abandoned files in the
        // container — and omitting the declaration entirely is a build warning.
        #expect(info["LSSupportsOpeningDocumentsInPlace"] as? Bool == true)
    }

    @Test("Build-setting substitutions in Info.plist actually expanded")
    func substitutionsExpanded() throws {
        let identifier = try #require(try info()["CFBundleIdentifier"] as? String)
        #expect(!identifier.contains("$("), "unexpanded build setting: \(identifier)")
        #expect(identifier == "com.brogwalkerh.cardash")
    }
}
