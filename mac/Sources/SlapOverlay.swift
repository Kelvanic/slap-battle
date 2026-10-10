import AppKit
import SwiftUI

/// Click-through, transparent window over the active screen that plays the incoming-slap cinematic.
@MainActor
final class SlapOverlayController {
  private var window: NSWindow?
  private var generation = 0

  func show(from: String, kind: String) {
    guard let screen = NSScreen.main else { return }
    let w = window ?? makeWindow()
    w.setFrame(screen.frame, display: false)
    w.contentView = NSHostingView(rootView: SlapOverlayView(from: from, kind: kind))
    w.orderFrontRegardless()
    window = w
    generation += 1
    let g = generation
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(2300))
      guard let self, self.generation == g else { return }
      self.window?.orderOut(nil)
    }
  }

  func hide() {
    generation += 1
    window?.orderOut(nil)
  }

  private func makeWindow() -> NSWindow {
    let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.level = .screenSaver
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    return w
  }
}

private struct Particle: Identifiable {
  let id = UUID()
  let emoji: String
  let angle: Double
  let distance: CGFloat
  let spin: Double
  let size: CGFloat
}

private struct ShakeEffect: GeometryEffect {
  var animatableData: CGFloat
  func effectValue(size: CGSize) -> ProjectionTransform {
    let decay = 1 - animatableData
    return ProjectionTransform(CGAffineTransform(
      translationX: sin(animatableData * .pi * 9) * 26 * decay,
      y: cos(animatableData * .pi * 7) * 12 * decay))
  }
}

struct SlapOverlayView: View {
  let from: String
  let kind: String

  @State private var handIn = false
  @State private var impact = false
  @State private var showText = false
  @State private var flash: Double = 0
  @State private var ringScale: CGFloat = 0.2
  @State private var ringOpacity: Double = 0
  @State private var burst = false
  @State private var particlesGone = false
  @State private var shake: CGFloat = 0
  @State private var fade = false
  @State private var particles: [Particle] = []

  private var tint: Color { Theme.color[kind] ?? .pink }
  private var hand: String { Theme.emoji[kind] ?? "👋" }

  var body: some View {
    ZStack {
      RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0.15), .clear], center: .center, startRadius: 0, endRadius: 900)
        .opacity(flash)
        .ignoresSafeArea()

      Circle()
        .stroke(tint, lineWidth: 22)
        .frame(width: 240, height: 240)
        .scaleEffect(ringScale)
        .opacity(ringOpacity)

      Circle()
        .stroke(.white, lineWidth: 6)
        .frame(width: 240, height: 240)
        .scaleEffect(ringScale * 0.75)
        .opacity(ringOpacity * 0.8)

      ForEach(particles) { p in
        Text(p.emoji)
          .font(.system(size: p.size))
          .offset(x: burst ? cos(p.angle) * p.distance : 0,
                  y: burst ? sin(p.angle) * p.distance : 0)
          .rotationEffect(.degrees(burst ? p.spin : 0))
          .opacity(burst && !particlesGone ? 1 : 0)
      }

      Text(hand)
        .font(.system(size: 280))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .rotationEffect(.degrees(handIn ? (impact ? -6 : 14) : -70))
        .scaleEffect(impact ? 1 : 1.45)
        .offset(x: handIn ? 0 : -1200, y: handIn ? -40 : 260)

      VStack(spacing: 4) {
        HStack(spacing: 10) {
          Avatar(name: from, size: 40)
          Text(from).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        Text("\(Theme.verb[kind] ?? "SLAPPED") YOU!")
          .font(.system(size: 72, weight: .black, design: .rounded))
          .foregroundStyle(LinearGradient(colors: [.yellow, .orange, tint], startPoint: .leading, endPoint: .trailing))
          .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
      }
      .padding(.horizontal, 44).padding(.vertical, 22)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(.white.opacity(0.25)))
      .scaleEffect(showText ? 1 : 0.2)
      .opacity(showText ? 1 : 0)
      .offset(y: 250)
    }
    .modifier(ShakeEffect(animatableData: shake))
    .opacity(fade ? 0 : 1)
    .task { await play() }
  }

  private func play() async {
    let pool = [hand, hand, "💥", "⭐️", "✨", "💫", "😵‍💫"]
    particles = (0..<30).map { _ in
      Particle(emoji: pool.randomElement() ?? hand,
               angle: .random(in: 0..<(2 * .pi)),
               distance: .random(in: 200...560),
               spin: .random(in: -600...600),
               size: .random(in: 26...60))
    }

    withAnimation(.easeIn(duration: 0.24)) { handIn = true }
    try? await Task.sleep(for: .milliseconds(240))

    flash = 1
    ringOpacity = 0.95
    try? await Task.sleep(for: .milliseconds(16))

    withAnimation(.spring(response: 0.32, dampingFraction: 0.42)) { impact = true }
    withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.08)) { showText = true }
    withAnimation(.easeOut(duration: 0.75)) { ringScale = 4.2; ringOpacity = 0; burst = true }
    withAnimation(.easeOut(duration: 0.6)) { flash = 0 }
    withAnimation(.linear(duration: 0.5)) { shake = 1 }

    try? await Task.sleep(for: .milliseconds(900))
    withAnimation(.easeIn(duration: 0.5)) { particlesGone = true }
    try? await Task.sleep(for: .milliseconds(650))
    withAnimation(.easeIn(duration: 0.35)) { fade = true }
  }
}
