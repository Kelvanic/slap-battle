import SwiftUI

/// Owns the long-lived relay + effects; connects at launch, not when the menu first opens.
@MainActor
final class AppModel: ObservableObject {
  let relay = RelayClient()
  let fx = SlapFX()
  private var debugWindow: NSWindow?

  init() {
    relay.onSlapped = { [fx] from, kind in fx.fire(kind: kind, from: from) }
    relay.connect()
    // Dev aid: SLAP_DEBUG_WINDOW=1 also shows the panel in a regular window
    // (menu bar icons can be hidden by the notch).
    if ProcessInfo.processInfo.environment["SLAP_DEBUG_WINDOW"] == "1" {
      let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 360, height: 560),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
      w.title = "SlapBattle (debug)"
      w.contentView = NSHostingView(rootView: ContentView(relay: relay, fx: fx))
      w.makeKeyAndOrderFront(nil)
      debugWindow = w
    }
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
  var gradient: LinearGradient {
    switch self {
    case .solo: LinearGradient(colors: [.gray, Color(white: 0.35)], startPoint: .leading, endPoint: .trailing)
    case .crew: LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing)
    case .arena: Theme.hot
    }
  }
}

struct ContentView: View {
  @ObservedObject var relay: RelayClient
  @ObservedObject var fx: SlapFX
  @State private var room = ""
  @State private var diceSpin = 0.0
  @Namespace private var modeNS

  var body: some View {
    VStack(spacing: 14) {
      header
      HStack(spacing: 10) {
        StatPill(icon: "👋", label: "Dealt", value: relay.sent, tint: .pink)
        StatPill(icon: "🤕", label: "Taken", value: relay.taken, tint: .orange)
      }
      modePicker
      if relay.mode == Mode.crew.rawValue {
        roomBar.transition(.move(edge: .top).combined(with: .opacity))
      }
      if let h = relay.lastHitFrom, relay.peers.contains(h) {
        slapBack(h).transition(.scale(scale: 0.8).combined(with: .opacity))
      }
      peers
      if !relay.feed.isEmpty { feed }
      footer
    }
    .padding(16)
    .frame(width: 360)
    .background { AnimatedBackdrop() }
    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: relay.mode)
    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: relay.lastHitFrom)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Avatar(name: relay.name, size: 46)
        .id(relay.name)
        .transition(.scale.combined(with: .opacity))
      VStack(alignment: .leading, spacing: 1) {
        Text("You are").font(.caption2.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
        Text(relay.name)
          .font(.system(.title3, design: .rounded).weight(.heavy))
          .contentTransition(.interpolate)
          .lineLimit(1)
      }
      Spacer()
      Button {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) { diceSpin += 360 }
        relay.send(["t": "regen_name"])
      } label: {
        Text("🎲").font(.system(size: 26)).rotationEffect(.degrees(diceSpin))
      }
      .buttonStyle(BouncyButtonStyle())
      .help("Roll a new random name")
    }
  }

  private var modePicker: some View {
    HStack(spacing: 4) {
      ForEach(Mode.allCases) { m in
        let selected = relay.mode == m.rawValue
        Button { select(m) } label: {
          HStack(spacing: 5) {
            Text(m.icon)
            Text(m.title).font(.system(.callout, design: .rounded).weight(.bold))
          }
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity)
          .foregroundStyle(selected ? Color.white : Color.primary)
          .background {
            if selected {
              Capsule().fill(m.gradient)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .matchedGeometryEffect(id: "pill", in: modeNS)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(.thinMaterial, in: Capsule())
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
        .background(Mode.crew.gradient, in: Capsule())
        .disabled(room.isEmpty)
        .opacity(room.isEmpty ? 0.5 : 1)
    }
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func slapBack(_ who: String) -> some View {
    Button {
      relay.send(["t": "slap", "to": who, "kind": "slap"])
    } label: {
      HStack(spacing: 8) {
        Text("↩️").font(.title3)
        Text("Slap ").fontWeight(.bold) + Text(who).fontWeight(.black) + Text(" back!").fontWeight(.bold)
      }
      .font(.system(.callout, design: .rounded))
      .lineLimit(1)
      .foregroundStyle(.white)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity)
      .background(Theme.hot, in: Capsule())
      .phaseAnimator([false, true]) { v, p in
        v.scaleEffect(p ? 1.03 : 1).shadow(color: .pink.opacity(p ? 0.7 : 0.2), radius: p ? 14 : 4)
      } animation: { _ in .easeInOut(duration: 0.7) }
    }
    .buttonStyle(BouncyButtonStyle())
  }

  private var peers: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        PulseDot(on: !relay.peers.isEmpty)
        Text("Online · \(relay.peers.count)")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
          .contentTransition(.numericText(value: Double(relay.peers.count)))
        Spacer()
        if let r = relay.room, relay.mode == Mode.crew.rawValue {
          Text("#\(r)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.teal)
        }
      }
      if relay.peers.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 6) {
            ForEach(relay.peers, id: \.self) { peer in
              PeerRow(
                name: peer,
                kinds: relay.kinds,
                onSlap: { k in relay.send(["t": "slap", "to": peer, "kind": k]) },
                onBlock: { relay.send(["t": "block", "name": peer]) },
                onReport: { relay.send(["t": "report", "name": peer]) })
              .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .scale(scale: 0.6).combined(with: .opacity)))
            }
          }
          .padding(.vertical, 2)
        }
        .frame(maxHeight: 230)
      }
    }
  }

  private var emptyState: some View {
    let (icon, text): (String, String) = switch relay.mode {
    case Mode.solo.rawValue: ("😇", "Solo mode — nobody can slap you.")
    case Mode.crew.rawValue: ("📡", "Waiting for your crew… share the room code.")
    default: ("🥊", "Arena's empty. Be the first to throw hands.")
    }
    return VStack(spacing: 6) {
      Text(icon).font(.system(size: 38))
        .phaseAnimator([0.0, -6.0]) { v, y in v.offset(y: y) } animation: { _ in .easeInOut(duration: 0.8) }
      Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        .foregroundStyle(item.incoming ? Color.orange : Color.primary)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 10) {
      PulseDot(on: relay.connected)
      Text(relay.connected ? "Live" : "Reconnecting…").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Spacer()
      Button {
        withAnimation(.spring) { fx.panicked ? fx.unpanic() : fx.panic() }
      } label: {
        Label(fx.panicked ? "Resume" : "Panic", systemImage: fx.panicked ? "play.fill" : "hand.raised.slash.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(fx.panicked ? Color.green : Color.red, in: Capsule())
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
