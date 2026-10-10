import AppKit
import AVFoundation

/// Incoming-slap effects: sound + full-screen flash + shake.
/// Never raises volume; respects mute. Panic flag kills effects instantly.
@MainActor
final class SlapFX: ObservableObject {
  @Published var panicked = false
  private var player: AVAudioPlayer?
  private var flashWindow: NSWindow?

  /// kind is relay-validated preset; unknown kinds fall back to slap asset.
  func fire(kind: String, from: String) {
    guard !panicked else { return }
    playSound(kind: kind)
    flashBanner(from: from, kind: kind)
    shakeKeyWindow()
  }

  func panic() {
    panicked = true
    player?.stop()
    flashWindow?.orderOut(nil)
    flashWindow = nil
  }

  func unpanic() { panicked = false }

  private func playSound(kind: String) {
    let candidates = [kind, "slap"]
    for c in candidates {
      if let url = Bundle.main.url(forResource: c, withExtension: "wav"),
         let p = try? AVAudioPlayer(contentsOf: url) {
        p.volume = min(1.0, NSSound.systemVolume)
        p.play()
        player = p
        return
      }
    }
    NSSound.beep()
  }

  private func flashBanner(from: String, kind: String) {
    guard let screen = NSScreen.main else { return }
    let f = NSRect(x: screen.frame.midX - 220, y: screen.frame.midY - 60, width: 440, height: 120)
    let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.level = .floating
    w.ignoresMouseEvents = true
    let label = NSTextField(labelWithString: "\(emoji(kind)) \(from) slapped you!")
    label.font = .boldSystemFont(ofSize: 30)
    label.alignment = .center
    label.textColor = .white
    label.backgroundColor = NSColor.black.withAlphaComponent(0.75)
    label.wantsLayer = true
    label.layer?.cornerRadius = 16
    w.contentView = label
    w.orderFrontRegardless()
    flashWindow = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak w] in
      if self?.flashWindow === w { w?.orderOut(nil); self?.flashWindow = nil }
    }
  }

  private static let EMOJI: [String: String] = ["slap": "👋", "bonk": "🔨", "splat": "💥", "thwack": "🫳"]
  private func emoji(_ kind: String) -> String { Self.EMOJI[kind] ?? "👋" }

  private func shakeKeyWindow() {
    guard let w = NSApp.keyWindow else { return }
    let origin = w.frame.origin
    let dx: [CGFloat] = [-14, 12, -10, 8, -5, 3, 0]
    for (i, d) in dx.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.035) {
        w.setFrameOrigin(NSPoint(x: origin.x + d, y: origin.y))
      }
    }
  }
}

private extension NSSound {
  /// Current system output volume 0…1; best-effort, defaults to 0.5.
  static var systemVolume: Float {
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", "output volume of (get volume settings)"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    task.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (Float(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50) / 100
  }
}
