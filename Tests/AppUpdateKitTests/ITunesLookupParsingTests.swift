import Foundation
import Testing

@testable import AppUpdateKit

struct ITunesLookupParsingTests {
    @Test func parsesARealLookupPayloadShape() throws {
        let json = """
        {
          "resultCount": 1,
          "results": [{
            "trackName": "MONO 记账",
            "version": "26.15.0",
            "releaseNotes": "• Bug fixes\\n• Performance improvements",
            "currentVersionReleaseDate": "2026-08-01T07:00:00Z",
            "trackViewUrl": "https://apps.apple.com/cn/app/id6670716062",
            "bundleId": "com.example.mono",
            "artworkUrl512": "https://example.com/icon.png",
            "minimumOsVersion": "17.0"
          }]
        }
        """
        let release = try ITunesLookupClient.parse(Data(json.utf8))

        #expect(release?.appName == "MONO 记账")
        #expect(release?.version == "26.15.0")
        #expect(release?.releaseNotes?.contains("Bug fixes") == true)
        #expect(release?.releaseDate != nil)
        #expect(release?.storeURL.absoluteString == "https://apps.apple.com/cn/app/id6670716062")
        #expect(release?.iconURL?.absoluteString == "https://example.com/icon.png")
    }

    @Test func emptyResultsParseAsNoListing() throws {
        let json = #"{"resultCount": 0, "results": []}"#
        let release = try ITunesLookupClient.parse(Data(json.utf8))
        #expect(release == nil)
    }

    @Test func missingReleaseNotesAndDateAreTolerated() throws {
        let json = """
        {
          "resultCount": 1,
          "results": [{
            "trackName": "App",
            "version": "1.0.1",
            "trackViewUrl": "https://apps.apple.com/app/id1"
          }]
        }
        """
        let release = try ITunesLookupClient.parse(Data(json.utf8))
        #expect(release?.version == "1.0.1")
        #expect(release?.releaseNotes == nil)
        #expect(release?.releaseDate == nil)
        #expect(release?.iconURL == nil)
    }
}
