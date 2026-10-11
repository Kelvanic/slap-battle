import SwiftUI

/// Owns the long-lived relay + effects; connects at launch, not when the menu first opens.
@MainActor
final class AppModel: ObservableObject {
  let relay = RelayClient()
  let fx = SlapFX()

  init() {
    relay.onSlapped = { [fx] from, kind in fx.fire(kind: kind, from: from) }
    relay.connect()
  }
}

@main
struct SlapBattleApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      ContentView(relay: model.relay, fx: model.fx)
    } label: {
      MenuBarIcon(relay: model.relay)
    }
    .menuBarExtraStyle(.window)
  }
}

struct MenuBarIcon: View {
  @ObservedObject var relay: RelayClient
  var body: some View {
    Image(systemName: relay.taken > 0 ? "hand.raised.fill" : "hand.raised")
      .symbolEffect(.bounce, value: relay.taken)
  }
}

enum Mode: String, CaseIterable, Identifiable {
  case solo = "private", crew, arena
  var id: String { rawValue }
  var icon: String { switch self { case .solo: "🔒"; case .crew: "👥"; case .arena: "⚔️" } }
  var title: String { switch self { case .solo: "Solo"; case .crew: "Crew"; case .arena: "Arena" } }
}

struct ContentView: View {
  @ObservedObject var relay: RelayClient
  @ObservedObject var fx: SlapFX
  @State private var room = ""
  @State private var kind = "slap"
  @Namespace private var modeNS

  var body: some View {
    VStack(spacing: 14) {
      header
      HStack(spacing: 10) {
        StatPill(icon: "👋", label: "Dealt", value: relay.sent)
        StatPill(icon: "🤕", label: "Taken", value: relay.taken)
      }
      modePicker
      if relay.mode == Mode.crew.rawValue {
        roomBar.transition(.move(edge: .top).combined(with: .opacity))
      }
      if relay.mode != Mode.solo.rawValue {
        weaponPicker.transition(.move(edge: .top).combined(with: .opacity))
      }
      if let h = relay.lastHitFrom, relay.mode != Mode.solo.rawValue {
        slapBack(h).transition(.scale(scale: 0.8).combined(with: .opacity))
      }
      peers
      if !relay.feed.isEmpty { feed }
      if let error = relay.statusError {
        Label(error, systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(Theme.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
      footer
    }
    .padding(16)
    .frame(width: 360)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: relay.mode)
    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: relay.lastHitFrom)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Avatar(name: relay.name, size: 46)
        .id(relay.name)
        .transition(.scale.combined(with: .opacity))
      VStack(alignment: .leading, spacing: 1) {
        Text("Your name").font(.caption2.weight(.medium)).foregroundStyle(.secondary).textCase(.uppercase)
        Text(relay.name)
          .font(.title3.weight(.semibold))
          .contentTransition(.interpolate)
          .lineLimit(1)
      }
      Spacer()
      Image(systemName: "person.crop.circle.badge.checkmark")
        .font(.title3)
        .foregroundStyle(.secondary)
        .help("Your name stays with this Mac's local Keychain identity.")
    }
  }

  private var modePicker: some View {
    HStack(spacing: 4) {
      ForEach(Mode.allCases) { m in
        let selected = relay.mode == m.rawValue
        Button { select(m) } label: {
          HStack(spacing: 5) {
            Text(m.icon)
            Text(m.title).font(.callout.weight(.medium))
          }
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity)
          .foregroundStyle(selected ? Color.primary : Color.secondary)
          .background {
            if selected {
              Capsule().fill(Theme.selection)
                .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                .matchedGeometryEffect(id: "pill", in: modeNS)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(Theme.inset, in: Capsule())
  }

  private var roomBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "number").foregroundStyle(.secondary)
      TextField(relay.room ?? "room-code", text: $room)
        .textFieldStyle(.plain)
        .font(.system(.callout, design: .monospaced))
        .onSubmit { joinRoom() }
        .onChange(of: room) { _, new in
          let f = String(new.lowercased().filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }.prefix(32))
          if f != new { room = f }
        }
      Button("Join", action: joinRoom)
        .buttonStyle(.plain)
        .font(.callout.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.actionFill, in: Capsule())
        .disabled(room.isEmpty)
        .opacity(room.isEmpty ? 0.5 : 1)
    }
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func slapBack(_ who: String) -> some View {
    Button {
      relay.send(["t": "slap", "to": who, "kind": kind])
    } label: {
      HStack(spacing: 8) {
        Text("↩️").font(.title3)
        Text("Slap ").fontWeight(.medium) + Text(who).fontWeight(.semibold) + Text(" back!").fontWeight(.medium)
      }
      .font(.callout)
      .lineLimit(1)
      .foregroundStyle(Theme.accent)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity)
      .background(Theme.accent.opacity(0.08), in: Capsule())
      .phaseAnimator([false, true]) { v, p in
        v.scaleEffect(p ? 1.015 : 1)
      } animation: { _ in .easeInOut(duration: 0.7) }
    }
    .buttonStyle(BouncyButtonStyle())
  }

  private var weaponPicker: some View {
    HStack(spacing: 8) {
      Text("Weapon").font(.caption.weight(.bold)).foregroundStyle(.secondary)
      Spacer()
      ForEach(relay.kinds, id: \.self) { k in
        let selected = kind == k
        let tint = Theme.color[k] ?? Theme.accent
        Button {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { kind = k }
        } label: {
          Text(Theme.emoji[k] ?? "👋")
            .font(.system(size: selected ? 22 : 17))
            .frame(width: 38, height: 38)
            .background(Circle().fill(tint.opacity(selected ? 0.10 : 0.025)))
            .overlay(Circle().strokeBorder(tint.opacity(selected ? 0.6 : 0), lineWidth: 1))
            .scaleEffect(selected ? 1.08 : 1)
        }
        .buttonStyle(BouncyButtonStyle())
        .help(k.capitalized)
      }
    }
  }

  private var countLabel: String {
    switch relay.mode {
    case Mode.arena.rawValue: "\(relay.onlineCount.formatted()) in the arena"
    case Mode.crew.rawValue: "\(relay.onlineCount.formatted()) in the crew"
    default: "Offline to everyone"
    }
  }

  private var randomSlapButton: some View {
    let canSlap = relay.onlineCount > 1
    return PopButton(emoji: Theme.emoji[kind] ?? "👋") {
      relay.slapRandom(kind)
    } label: {
      HStack(spacing: 10) {
        Text("🎯").font(.title2)
        VStack(alignment: .leading, spacing: 0) {
          Text("Slap a random stranger").font(.callout.weight(.semibold))
          Text("out of \(max(relay.onlineCount - 1, 0).formatted()) people")
            .font(.caption2.weight(.semibold))
            .contentTransition(.numericText(value: Double(relay.onlineCount)))
            .opacity(0.85)
        }
        Spacer()
        Text(Theme.emoji[kind] ?? "👋").font(.title2)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(Theme.actionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .disabled(!canSlap)
    .opacity(canSlap ? 1 : 0.45)
  }

  private var peers: some View {
    let inArena = relay.mode == Mode.arena.rawValue
    let rivals = inArena ? relay.rivals : []
    let strangers = relay.peers.filter { !rivals.contains($0) }
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        PulseDot(on: relay.onlineCount > 1)
        Text(countLabel)
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
          .contentTransition(.numericText(value: Double(relay.onlineCount)))
        Spacer()
        if let r = relay.room, relay.mode == Mode.crew.rawValue {
          Text("#\(r)").font(.caption.monospaced().weight(.medium)).foregroundStyle(Theme.accent)
        }
      }
      if inArena { randomSlapButton }
      if rivals.isEmpty && strangers.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            if !rivals.isEmpty {
              sectionTitle("🔥 Rivals")
              ForEach(rivals, id: \.self) { row($0, rival: true) }
            }
            if inArena && !strangers.isEmpty {
              HStack {
                sectionTitle("👀 Strangers")
                Spacer()
                Button { relay.shuffle() } label: {
                  Label("Shuffle", systemImage: "shuffle").font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(BouncyButtonStyle())
                .help("Show different random people")
              }
            }
            ForEach(strangers, id: \.self) { row($0, rival: false) }
          }
          .padding(.vertical, 2)
        }
        .frame(maxHeight: 260)
      }
    }
  }

  private func sectionTitle(_ s: String) -> some View {
    Text(s).font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 2)
  }

  private func row(_ peer: String, rival: Bool) -> some View {
    PeerRow(
      name: peer,
      kind: kind,
      rival: rival,
      onSlap: { relay.send(["t": "slap", "to": peer, "kind": kind]) },
      onBlock: {
        relay.send(["t": "block", "name": peer])
        withAnimation(.spring) {
          relay.peers.removeAll { $0 == peer }
          relay.rivals.removeAll { $0 == peer }
        }
      },
      onReport: { relay.send(["t": "report", "name": peer]) })
    .transition(.asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .scale(scale: 0.6).combined(with: .opacity)))
  }

  private var emptyState: some View {
    let (icon, text): (String, String) = switch relay.mode {
    case Mode.solo.rawValue: ("😇", "Solo mode — nobody can slap you.")
    case Mode.crew.rawValue: ("📡", "Waiting for your crew… share the room code.")
    default: relay.onlineCount > 1
      ? ("🎲", "Hit 🎯 above, or shuffle to see strangers.")
      : ("🥊", "Arena's empty. Be the first to throw hands.")
    }
    return VStack(spacing: 6) {
      Text(icon).font(.system(size: 38))
        .phaseAnimator([0.0, -6.0]) { v, y in v.offset(y: y) } animation: { _ in .easeInOut(duration: 0.8) }
      Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      if relay.mode == Mode.arena.rawValue && relay.onlineCount > 1 {
        Button("🔀 Shuffle") { relay.shuffle() }.buttonStyle(BouncyButtonStyle()).font(.callout.weight(.bold))
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var feed: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Recent").font(.caption.weight(.bold)).foregroundStyle(.secondary)
      ForEach(relay.feed) { item in
        HStack(spacing: 8) {
          Avatar(name: item.who, size: 20)
          Group {
            if item.incoming {
              Text(item.who).fontWeight(.bold) + Text(" \((Theme.verb[item.kind] ?? "slapped").lowercased()) you")
            } else {
              Text("You \((Theme.verb[item.kind] ?? "slapped").lowercased()) ") + Text(item.who).fontWeight(.bold)
            }
          }
          .font(.caption)
          .lineLimit(1)
          Spacer(minLength: 4)
          Text(Theme.emoji[item.kind] ?? "👋").font(.caption)
          Text(item.at, style: .relative).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .foregroundStyle(item.incoming ? Theme.accent : Color.secondary)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 10) {
      PulseDot(on: relay.connected)
      Text(relay.connected ? "Live" : relay.statusError == nil ? "Reconnecting…" : "Connection paused")
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Spacer()
      Button {
        withAnimation(.spring) { fx.panicked ? fx.unpanic() : fx.panic() }
      } label: {
        Label(fx.panicked ? "Resume" : "Panic", systemImage: fx.panicked ? "play.fill" : "hand.raised.slash.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(fx.panicked ? Theme.positive : Theme.warning)
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background((fx.panicked ? Theme.positive : Theme.warning).opacity(0.10), in: Capsule())
      }
      .buttonStyle(BouncyButtonStyle())
      .help(fx.panicked ? "Re-enable slap effects" : "Silence all incoming slap effects")
      Button { NSApp.terminate(nil) } label: {
        Image(systemName: "power").font(.caption.weight(.bold)).foregroundStyle(.secondary)
      }
      .buttonStyle(BouncyButtonStyle())
      .help("Quit")
    }
  }

  private func select(_ m: Mode) {
    guard relay.mode != m.rawValue else { return }
    relay.mode = m.rawValue
    if m == .crew {
      relay.send(["t": "set_mode", "mode": "crew", "room": room.isEmpty ? "lobby" : room])
    } else {
      relay.send(["t": "set_mode", "mode": m.rawValue])
    }
  }

  private func joinRoom() {
    guard !room.isEmpty else { return }
    relay.send(["t": "set_mode", "mode": "crew", "room": room])
  }
}
