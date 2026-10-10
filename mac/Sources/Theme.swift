import SwiftUI

enum Theme {
  static let emoji: [String: String] = ["slap": "👋", "bonk": "🔨", "splat": "💥", "thwack": "🫳"]
  static let verb: [String: String] = ["slap": "SLAPPED", "bonk": "BONKED", "splat": "SPLATTED", "thwack": "THWACKED"]
  static let color: [String: Color] = ["slap": .pink, "bonk": .orange, "splat": .purple, "thwack": .cyan]

  /// Stable per-name gradient so a player keeps their color everywhere.
  static func avatarGradient(for name: String) -> LinearGradient {
    var h: UInt64 = 1_469_598_103_934_665_603
    for b in name.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
    let hue = Double(h % 360) / 360
    return LinearGradient(
      colors: [Color(hue: hue, saturation: 0.75, brightness: 0.98),
               Color(hue: (hue + 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.72)],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  static let hot = LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing)
}

struct Avatar: View {
  let name: String
  var size: CGFloat = 32

  var body: some View {
    let initials = name.split(separator: "-").prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
    Circle()
      .fill(Theme.avatarGradient(for: name))
      .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
      .overlay(Text(initials).font(.system(size: size * 0.38, weight: .heavy, design: .rounded)).foregroundStyle(.white))
      .frame(width: size, height: size)
      .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
  }
}

struct BouncyButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.82 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
  }
}

/// Drifting blurred color blobs behind the panel. Only renders while the menu is open.
struct AnimatedBackdrop: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
      let t = ctx.date.timeIntervalSinceReferenceDate
      ZStack {
        blob(.pink, 230).offset(x: cos(t * 0.6) * 90, y: sin(t * 0.5) * 110 - 120)
        blob(.orange, 200).offset(x: sin(t * 0.4) * 100, y: cos(t * 0.7) * 100 + 140)
        blob(.purple, 250).offset(x: cos(t * 0.3 + 2) * 110, y: sin(t * 0.45 + 1) * 80)
      }
    }
    .allowsHitTesting(false)
  }

  private func blob(_ c: Color, _ d: CGFloat) -> some View {
    Circle().fill(c.opacity(0.32)).frame(width: d, height: d).blur(radius: 60)
  }
}

struct PulseDot: View {
  let on: Bool
  var body: some View {
    let c: Color = on ? .green : .red
    Circle().fill(c).frame(width: 8, height: 8)
      .background(
        Circle().fill(c.opacity(0.5))
          .phaseAnimator([false, true]) { v, p in v.scaleEffect(p ? 2.4 : 1).opacity(p ? 0 : 0.8) }
            animation: { p in p ? .easeOut(duration: 1.2) : .linear(duration: 0) }
      )
  }
}

struct StatPill: View {
  let icon: String
  let label: String
  let value: Int
  let tint: Color

  var body: some View {
    HStack(spacing: 8) {
      Text(icon).font(.title3)
      VStack(alignment: .leading, spacing: 0) {
        Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        Text("\(value)")
          .font(.system(.title3, design: .rounded).weight(.black))
          .contentTransition(.numericText(value: Double(value)))
          .foregroundStyle(tint)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: value)
  }
}

struct FloatingPop: View {
  let emoji: String
  @State private var go = false

  var body: some View {
    Text("+1 \(emoji)")
      .font(.system(.headline, design: .rounded).weight(.black))
      .foregroundStyle(Theme.hot)
      .offset(y: go ? -48 : 0)
      .scaleEffect(go ? 1.3 : 0.6)
      .opacity(go ? 0 : 1)
      .onAppear { withAnimation(.easeOut(duration: 0.85)) { go = true } }
      .allowsHitTesting(false)
  }
}

struct PeerRow: View {
  let name: String
  let kinds: [String]
  let onSlap: (String) -> Void
  let onBlock: () -> Void
  let onReport: () -> Void

  private struct Pop: Identifiable { let id = UUID(); let emoji: String }
  @State private var hover = false
  @State private var pops: [Pop] = []

  var body: some View {
    HStack(spacing: 10) {
      Avatar(name: name, size: 30)
      Text(name).font(.system(.callout, design: .rounded).weight(.semibold)).lineLimit(1)
      Spacer(minLength: 4)
      ForEach(kinds.prefix(4), id: \.self) { k in
        Button {
          let p = Pop(emoji: Theme.emoji[k] ?? "👋")
          pops.append(p)
          NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
          onSlap(k)
          Task { try? await Task.sleep(for: .milliseconds(900)); pops.removeAll { $0.id == p.id } }
        } label: {
          Text(Theme.emoji[k] ?? "👋").font(.system(size: 17))
            .frame(width: 30, height: 30)
            .background(Circle().fill((Theme.color[k] ?? .pink).opacity(hover ? 0.28 : 0.14)))
        }
        .buttonStyle(BouncyButtonStyle())
        .help(k.capitalized)
      }
      Menu {
        Button("Block \(name)", role: .destructive, action: onBlock)
        Button("Report \(name)", action: onReport)
      } label: {
        Image(systemName: "ellipsis").foregroundStyle(.secondary)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .frame(width: 18)
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.primary.opacity(hover ? 0.10 : 0.05))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(hover ? 0.18 : 0.06)))
    )
    .overlay(alignment: .trailing) {
      ZStack { ForEach(pops) { FloatingPop(emoji: $0.emoji) } }.offset(x: -60)
    }
    .scaleEffect(hover ? 1.015 : 1)
    .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
  }
}
