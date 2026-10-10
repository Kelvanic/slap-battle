import AppKit

/// Incoming-slap effects: system sound + fullscreen cinematic.
/// System sounds follow the user's output volume and mute; panic kills everything.
@MainActor
final class SlapFX: ObservableObject {
  @Published var panicked = false
  private let overlay = SlapOverlayController()
  private static let sound: [String: String] = ["slap": "Pop", "bonk": "Funk", "splat": "Frog", "thwack": "Basso"]

  func fire(kind: String, from: String) {
    guard !panicked else { return }
    NSSound(named: NSSound.Name(Self.sound[kind] ?? "Pop"))?.play()
    overlay.show(from: from, kind: kind)
  }

  func panic() {
    panicked = true
    overlay.hide()
  }

  func unpanic() { panicked = false }
}
