import SwiftUI

enum Theme {
  static let emoji: [String: String] = ["slap": "👋", "bonk": "🔨", "splat": "💥", "thwack": "🫳"]
  static let verb: [String: String] = ["slap": "SLAPPED", "bonk": "BONKED", "splat": "SPLATTED", "thwack": "THWACKED"]
  static let accent = adaptive(
    light: NSColor(srgbRed: 0.29, green: 0.40, blue: 0.50, alpha: 1),
    dark: NSColor(srgbRed: 0.65, green: 0.74, blue: 0.81, alpha: 1))
  static let actionFill = Color(red: 0.29, green: 0.40, blue: 0.50)
  static let positive = adaptive(
    light: NSColor(srgbRed: 0.36, green: 0.49, blue: 0.40, alpha: 1),
    dark: NSColor(srgbRed: 0.57, green: 0.70, blue: 0.60, alpha: 1))
  static let warning = adaptive(
    light: NSColor(srgbRed: 0.59, green: 0.36, blue: 0.31, alpha: 1),
    dark: NSColor(srgbRed: 0.80, green: 0.58, blue: 0.52, alpha: 1))
  static let surface = Color(nsColor: .windowBackgroundColor)
  static let selection = Color(nsColor: .controlBackgroundColor)
  static let inset = Color.primary.opacity(0.035)
  static let border = Color.primary.opacity(0.08)
  static let color: [String: Color] = [
    "slap": accent, "bonk": accent, "splat": accent, "thwack": accent
  ]

  /// Stable, muted identity colors rather than saturated avatar gradients.
  static func avatarColor(for name: String) -> Color {
    var h: UInt64 = 1_469_598_103_934_665_603
    for b in name.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
    return Color(hue: Double(h % 360) / 360, saturation: 0.19, brightness: 0.52)
  }

  private static func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
  }
}

struct Avatar: View {
  let name: String
  var size: CGFloat = 32

  var body: some View {
    let initials = name.split(separator: "-").prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
    Circle()
      .fill(Theme.avatarColor(for: name))
      .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
      .overlay(Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white))
      .frame(width: size, height: size)
  }
}

struct BouncyButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
  }
}


struct PulseDot: View {
  let on: Bool
  var body: some View {
    let c: Color = on ? Theme.positive : .secondary
    Circle().fill(c).frame(width: 6, height: 6)
      .background(
        Circle().fill(c.opacity(0.14))
          .phaseAnimator([false, true]) { v, p in v.scaleEffect(p ? 1.6 : 1).opacity(p ? 0 : 0.5) }
            animation: { p in p ? .easeOut(duration: 1.2) : .linear(duration: 0) }
      )
  }
}

struct StatPill: View {
  let icon: String
  let label: String
  let value: Int

  var body: some View {
    HStack(spacing: 8) {
      Text(icon).font(.title3)
      VStack(alignment: .leading, spacing: 0) {
        Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        Text("\(value)")
          .font(.system(.title3).weight(.semibold))
          .contentTransition(.numericText(value: Double(value)))
          .foregroundStyle(.primary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: value)
  }
}

struct FloatingPop: View {
  let emoji: String
  @State private var go = false

  var body: some View {
    Text("+1 \(emoji)")
      .font(.headline.weight(.semibold))
      .foregroundStyle(Theme.accent)
      .offset(y: go ? -48 : 0)
      .scaleEffect(go ? 1.3 : 0.6)
      .opacity(go ? 0 : 1)
      .onAppear { withAnimation(.easeOut(duration: 0.85)) { go = true } }
      .allowsHitTesting(false)
  }
}

/// Button that floats "+1 <emoji>" on every press, with a trackpad haptic tick.
struct PopButton<Label: View>: View {
  let emoji: String
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  private struct Pop: Identifiable { let id = UUID() }
  @State private var pops: [Pop] = []

  var body: some View {
    Button {
      let p = Pop()
      pops.append(p)
      NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
      action()
      Task { try? await Task.sleep(for: .milliseconds(900)); pops.removeAll { $0.id == p.id } }
    } label: {
      label()
    }
    .buttonStyle(BouncyButtonStyle())
    .overlay { ZStack { ForEach(pops) { _ in FloatingPop(emoji: emoji) } } }
  }
}

struct PeerRow: View {
  let name: String
  let kind: String
  var rival = false
  let onSlap: () -> Void
  let onBlock: () -> Void
  let onReport: () -> Void

  @State private var hover = false

  var body: some View {
    let tint = Theme.color[kind] ?? Theme.accent
    let emoji = Theme.emoji[kind] ?? "👋"
    HStack(spacing: 10) {
      Avatar(name: name, size: 30)
      VStack(alignment: .leading, spacing: 0) {
        Text(name).font(.callout.weight(.medium)).lineLimit(1)
        if rival {
          Text("rival").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      PopButton(emoji: emoji, action: onSlap) {
        HStack(spacing: 4) {
          Text(emoji)
          Text("Slap").fontWeight(.semibold)
        }
        .font(.callout)
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(tint.opacity(hover ? 0.14 : 0.08), in: Capsule())
      }
      .help("\(kind.capitalized) \(name)")
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
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.primary.opacity(hover ? 0.055 : 0.025))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
    )
    .scaleEffect(hover ? 1.015 : 1)
    .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
  }
}
