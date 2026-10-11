import Foundation
import Testing
@testable import SlapBattle

struct UpdateTests {
  @Test func numericVersionOrdering() {
    #expect(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.9")!)
    #expect(ReleaseVersion("2.0.0")! > ReleaseVersion("1.99.99")!)
    #expect(ReleaseVersion("v1.0.1")! > ReleaseVersion("1.0.0")!)
    #expect(ReleaseVersion("1.0.0") == ReleaseVersion("v1.0.0"))
  }

  @Test(arguments: ["", "1.0", "1.0.0-beta", "1.-1.0", "1.0.0.1", "1.0.x", "999999999999999999999999999999.0.0"])
  func malformedVersionsAreNotOffered(_ text: String) {
    #expect(ReleaseVersion(text) == nil)
  }

  private func release(
    version: String = "1.1.0", draft: Bool = false, prerelease: Bool = false,
    architecture: String = "arm64", pageHost: String = "github.com", assetHost: String = "github.com"
  ) throws -> Data {
    let asset = "SlapBattle-\(version)-macos-\(architecture).dmg"
    return try JSONSerialization.data(withJSONObject: [
      "tag_name": "v\(version)", "html_url": "https://\(pageHost)/Kelvanic/slap-battle/releases/tag/v\(version)",
      "draft": draft, "prerelease": prerelease,
      "assets": [["name": asset, "state": "uploaded",
                  "browser_download_url": "https://\(assetHost)/Kelvanic/slap-battle/releases/download/v\(version)/\(asset)"]]
    ])
  }

  @Test func selectsCurrentArchitecture() throws {
    let data = try release(architecture: "x86_64")
    let found = try ReleaseUpdate.parse(data, installed: ReleaseVersion("1.0.0")!, architecture: "x86_64")
    #expect(found?.version == ReleaseVersion("1.1.0"))
    #expect(found?.downloadURL.lastPathComponent == "SlapBattle-1.1.0-macos-x86_64.dmg")
    #expect(throws: UpdateError.self) {
      try ReleaseUpdate.parse(data, installed: ReleaseVersion("1.0.0")!, architecture: "arm64")
    }
  }

  @Test func doesNotOfferEqualOrOlderRelease() throws {
    for version in ["1.0.0", "0.9.9"] {
      #expect(try ReleaseUpdate.parse(release(version: version), installed: ReleaseVersion("1.0.0")!, architecture: "arm64") == nil)
    }
  }

  @Test func draftsAndPrereleasesAreExcluded() throws {
    #expect(try ReleaseUpdate.parse(release(draft: true), installed: ReleaseVersion("1.0.0")!, architecture: "arm64") == nil)
    #expect(try ReleaseUpdate.parse(release(prerelease: true), installed: ReleaseVersion("1.0.0")!, architecture: "arm64") == nil)
  }

  @Test func rejectsUntrustedDownloadLocations() throws {
    #expect(throws: UpdateError.self) {
      try ReleaseUpdate.parse(release(assetHost: "example.com"), installed: ReleaseVersion("1.0.0")!, architecture: "arm64")
    }
    #expect(throws: UpdateError.self) {
      try ReleaseUpdate.parse(release(pageHost: "example.com"), installed: ReleaseVersion("1.0.0")!, architecture: "arm64")
    }
  }
}
