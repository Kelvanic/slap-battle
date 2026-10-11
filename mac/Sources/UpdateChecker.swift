import AppKit
import Foundation
import UserNotifications

struct ReleaseVersion: Comparable, Equatable {
  let major: Int
  let minor: Int
  let patch: Int

  init?(_ text: String) {
    let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
          parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
          let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    return lhs.patch < rhs.patch
  }

  var description: String { "\(major).\(minor).\(patch)" }
}

struct ReleaseUpdate: Equatable {
  let version: ReleaseVersion
  let pageURL: URL
  let downloadURL: URL

  private struct Release: Decodable {
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
  }

  private struct Asset: Decodable {
    let name: String
    let browser_download_url: URL
    let state: String
  }

  /// Only offer a stable, newer release with an uploaded package for this architecture.
  static func parse(_ data: Data, installed: ReleaseVersion, architecture: String) throws -> Self? {
    let release = try JSONDecoder().decode(Release.self, from: data)
    guard !release.draft, !release.prerelease,
          let version = ReleaseVersion(release.tag_name), installed < version else { return nil }
    let tag = "v\(version.description)"
    guard release.tag_name == tag,
          release.html_url.scheme == "https", release.html_url.host == "github.com",
          release.html_url.path == "/Kelvanic/slap-battle/releases/tag/\(tag)",
          let asset = release.assets.first(where: {
            $0.name == "SlapBattle-\(version.description)-macos-\(architecture).dmg" && $0.state == "uploaded"
          }),
          asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
          asset.browser_download_url.path == "/Kelvanic/slap-battle/releases/download/\(tag)/\(asset.name)" else {
      throw UpdateError.packageUnavailable
    }
    return Self(version: version, pageURL: release.html_url, downloadURL: asset.browser_download_url)
  }
}

enum UpdateError: LocalizedError {
  case packageUnavailable
  var errorDescription: String? { "The newer release has no verified download link for this Mac yet." }
}

@MainActor
final class UpdateChecker: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  @Published private(set) var available: ReleaseUpdate?
  @Published private(set) var isChecking = false
  @Published private(set) var status: String?
  @Published private(set) var notificationStatus: String?
  @Published private(set) var notificationsEnabled = false
  let installedVersion: ReleaseVersion?
  private let session: URLSession
  private let defaults: UserDefaults
  private let architecture: String
  private var automaticChecks: Task<Void, Never>?
  private var center: UNUserNotificationCenter?
  private static let endpoint = URL(string: "https://api.github.com/repos/Kelvanic/slap-battle/releases/latest")!
  private static let notificationPrefix = "slapbattle.update."

  init(
    installedVersion: ReleaseVersion? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      .flatMap { $0 as? String }.flatMap(ReleaseVersion.init),
    architecture: String = UpdateChecker.buildArchitecture,
    session: URLSession = URLSession(configuration: .ephemeral),
    defaults: UserDefaults = .standard
  ) {
    self.installedVersion = installedVersion
    self.architecture = architecture
    self.session = session
    self.defaults = defaults
    super.init()
  }

  static var buildArchitecture: String {
    #if arch(arm64)
    return "arm64"
    #else
    return "x86_64"
    #endif
  }

  func start() {
    guard automaticChecks == nil else { return }
    // UserNotifications requires a real app bundle; swift run remains usable without it.
    if Bundle.main.bundleIdentifier == "com.kelvanic.slapbattle" {
      center = UNUserNotificationCenter.current()
      center?.delegate = self
    }
    automaticChecks = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.refreshNotificationStatus()
        await self.check()
        do { try await Task.sleep(for: .seconds(6 * 60 * 60)) } catch { return }
      }
    }
  }

  func check(showStatus: Bool = false) async {
    guard !isChecking else { return }
    guard let installedVersion else {
      status = "Version unavailable. Use the installed app to check for updates."
      return
    }
    isChecking = true
    status = nil
    defer { isChecking = false }
    do {
      var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("SlapBattle/\(installedVersion.description)", forHTTPHeaderField: "User-Agent")
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 1_048_576 else {
        status = "Couldn't check for updates. Try again later."
        return
      }
      available = try ReleaseUpdate.parse(data, installed: installedVersion, architecture: architecture)
      status = available == nil && showStatus ? "You're up to date (\(installedVersion.description))." : nil
      await notifyIfNeeded()
    } catch {
      status = error is UpdateError ? error.localizedDescription : "Couldn't check for updates. Try again later."
    }
  }

  func enableNotifications() async {
    guard let center else {
      notificationStatus = "Notifications require the installed Slap Battle app."
      return
    }
    do {
      _ = try await center.requestAuthorization(options: [.alert])
      await refreshNotificationStatus()
      if !notificationsEnabled {
        notificationStatus = "Allow Slap Battle in System Settings → Notifications. Updates still appear here."
      } else {
        notificationStatus = nil
        await notifyIfNeeded()
      }
    } catch {
      notificationStatus = "Couldn't enable notifications. Updates still appear in this panel."
    }
  }

  private func refreshNotificationStatus() async {
    guard let center else { return }
    notificationsEnabled = await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        continuation.resume(returning: enabled)
      }
    }
  }

  private func notifyIfNeeded() async {
    guard let center, let available else { return }
    let version = available.version.description
    guard defaults.string(forKey: "updates.lastNotifiedVersion") != version else { return }
    await refreshNotificationStatus()
    guard notificationsEnabled else { return }
    let content = UNMutableNotificationContent()
    content.title = "Slap Battle \(version) is available"
    content.body = "Open the release notes and download the update for your Mac."
    let request = UNNotificationRequest(identifier: Self.notificationPrefix + version, content: content, trigger: nil)
    do {
      try await center.add(request)
      defaults.set(version, forKey: "updates.lastNotifiedVersion")
    } catch {
      notificationStatus = "Update available; system notification couldn't be delivered."
    }
  }

  func openRelease() {
    guard let available else { return }
    NSWorkspace.shared.open(available.pageURL)
  }

  func openDownload() {
    guard let available else { return }
    NSWorkspace.shared.open(available.downloadURL)
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    await openNotification(identifier: response.notification.request.identifier)
  }

  private func openNotification(identifier: String) {
    guard identifier.hasPrefix(Self.notificationPrefix),
          let version = ReleaseVersion(String(identifier.dropFirst(Self.notificationPrefix.count))),
          let url = URL(string: "https://github.com/Kelvanic/slap-battle/releases/tag/v\(version.description)") else { return }
    NSWorkspace.shared.open(url)
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }
}
