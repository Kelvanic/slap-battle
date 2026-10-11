import SwiftUI

/// Owns the long-lived relay + effects; connects at launch, not when the menu first opens.
@MainActor
final class AppModel: ObservableObject {
  let relay = RelayClient()
  let fx = SlapFX()
  let updates = UpdateChecker()

  init() {
    relay.onSlapped = { [fx] from, kind in fx.fire(kind: kind, from: from) }
    relay.connect()
  }
}

@main
enum SlapBattleApp {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    let menuBar = MenuBarController()
    app.delegate = menuBar
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(menuBar) {}
  }
}

enum Mode: String, CaseIterable, Identifiable {
  case solo = "private", crew, arena
  var id: String { rawValue }
  var icon: String { switch self { case .solo: "lock"; case .crew: "person.2"; case .arena: "hand.raised" } }
  var title: String { switch self { case .solo: "Solo"; case .crew: "Crew"; case .arena: "Arena" } }
}

struct ContentView: View {
  @ObservedObject var relay: RelayClient
  @ObservedObject var fx: SlapFX
  @ObservedObject var updates: UpdateChecker
  @State private var room = ""
  @State private var kind = "slap"
  @State private var showActivity = false
  @State private var peerListHeight: CGFloat = 210
  @Namespace private var modeNS

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      toolbar
      identity
      if let release = updates.available { updateBanner(release) }
      modePicker
      if relay.mode == Mode.solo.rawValue {
        quietState
      } else {
        playArea
      }
      if fx.panicked {
        Label("Effects paused. You can still send slaps.", systemImage: "pause.circle")
          .font(.caption).foregroundStyle(Theme.warning)
      }
      if let error = relay.statusError {
        Label(error, systemImage: "exclamationmark.circle")
          .font(.caption).foregroundStyle(Theme.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !relay.feed.isEmpty { activity }
      if let status = updates.status {
        Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let status = updates.notificationStatus {
        Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider().opacity(0.55)
      footer
    }
    .padding(18)
    .frame(width: 360)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .animation(.easeInOut(duration: 0.2), value: relay.mode)
    .animation(.easeInOut(duration: 0.2), value: showActivity)
    .onChange(of: relay.onlineCount) { _, count in
      if relay.mode == Mode.arena.rawValue && count > 1 && relay.peers.isEmpty {
        relay.shuffle()
      }
    }
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Image(systemName: "hand.raised.fill").foregroundStyle(Theme.accent)
      Text("Slap Battle").font(.system(size: 14, weight: .semibold))
      Spacer()
      PulseDot(on: relay.connected)
      Text(relay.connected ? "Live" : relay.statusError == nil ? "Connecting" : "Paused")
        .font(.system(size: 11)).foregroundStyle(.secondary)
      Menu {
        Button(fx.panicked ? "Resume effects" : "Pause effects") { toggleEffects() }
        Button(updates.isChecking ? "Checking for updates…" : "Check for updates") {
          Task { await updates.check(showStatus: true) }
        }
        .disabled(updates.isChecking)
        if !updates.notificationsEnabled {
          Button("Enable update notifications") {
            Task { await updates.enableNotifications() }
          }
        }
        if let version = updates.installedVersion {
          Text("Version \(version.description)")
        }
        Divider()
        Button("Quit Slap Battle") { NSApp.terminate(nil) }
      } label: {
        Image(systemName: "ellipsis").frame(width: 20, height: 20)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("App options")
    }
  }
  private func updateBanner(_ release: ReleaseUpdate) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Version \(release.version.description) is available", systemImage: "arrow.down.circle")
        .font(.system(size: 12, weight: .semibold))
      Text("Review the release notes before installing. Your username stays the same.")
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 14) {
        Button("Download for this Mac") { updates.openDownload() }
          .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
        Button("Release notes") { updates.openRelease() }
          .buttonStyle(.plain).font(.system(size: 11))
      }
      .foregroundStyle(Theme.accent)
      if !updates.notificationsEnabled {
        Button("Notify me about updates") { Task { await updates.enableNotifications() } }
          .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
  }

  private var identity: some View {
    HStack(spacing: 10) {
      Avatar(name: relay.name, size: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(relay.name).font(.system(size: 13, weight: .semibold))
          .lineLimit(1).minimumScaleFactor(0.85)
        Label("Your name, for keeps", systemImage: "checkmark.shield")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .help("Your name is linked to this Mac's local Keychain identity.")
  }

  private var modePicker: some View {
    HStack(spacing: 3) {
      ForEach(Mode.allCases) { mode in
        let selected = relay.mode == mode.rawValue
        Button { select(mode) } label: {
          Label(mode.title, systemImage: mode.icon)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background {
              if selected {
                RoundedRectangle(cornerRadius: 6).fill(Theme.selection)
                  .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                  .matchedGeometryEffect(id: "mode", in: modeNS)
              }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) mode")
      }
    }
    .padding(3).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
    .disabled(!relay.connected)
  }

  private var quietState: some View {
    VStack(spacing: 10) {
      Image(systemName: "hand.raised")
        .font(.system(size: 25, weight: .light)).foregroundStyle(Theme.accent)
        .frame(width: 48, height: 48)
        .background(Theme.accent.opacity(0.06), in: Circle())
        .padding(.top, 4)
      Text("A little friendly chaos.").font(.system(size: 16, weight: .semibold))
      Text("You're in Solo. Join the arena to trade slaps,\nor play with friends in a crew.")
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).lineSpacing(3)
      Button { select(.arena) } label: {
        Label("Enter the arena", systemImage: "arrow.right")
          .font(.system(size: 13, weight: .semibold))
          .frame(maxWidth: .infinity).padding(.vertical, 10)
          .foregroundStyle(.white)
          .background(Theme.actionFill, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(BouncyButtonStyle()).disabled(!relay.connected)
      .padding(.top, 6)
      Text("Nobody can slap you until you join.")
        .font(.system(size: 10)).foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity)
  }

  private var playArea: some View {
    VStack(alignment: .leading, spacing: 12) {
      if relay.mode == Mode.crew.rawValue { roomBar }
      HStack {
        Text("Pick your move").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        Spacer()
        HStack(spacing: 5) {
          Circle().fill(Theme.positive).frame(width: 4, height: 4)
          Text("\(relay.onlineCount.formatted()) online")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .contentTransition(.numericText(value: Double(relay.onlineCount)))
        }
      }
      movePicker
      if relay.mode == Mode.arena.rawValue {
        Button {
          NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
          relay.slapRandom(kind)
        } label: {
          HStack(spacing: 8) {
            Text(Theme.emoji[kind] ?? "👋").font(.system(size: 17))
            Text("Slap a stranger").font(.system(size: 13, weight: .semibold))
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
          }
          .padding(.horizontal, 12).padding(.vertical, 11)
          .foregroundStyle(.white)
          .background(Theme.actionFill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(BouncyButtonStyle()).disabled(!relay.connected || relay.onlineCount < 2)
        .opacity(relay.onlineCount < 2 ? 0.55 : 1)
        .symbolEffect(.bounce, value: relay.sent)
      }
      if let opponent = relay.lastHitFrom,
         (relay.mode == Mode.arena.rawValue ? relay.rivals : relay.peers).contains(opponent) {
        Button { relay.send(["t": "slap", "to": opponent, "kind": kind]) } label: {
          Label("Slap \(opponent) back", systemImage: "arrow.uturn.backward")
            .font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(1)
        }
        .buttonStyle(.plain).disabled(!relay.connected)
      }
      opponentList
    }
  }

  private var movePicker: some View {
    HStack(spacing: 6) {
      ForEach(relay.kinds, id: \.self) { move in
        let selected = move == kind
        Button { withAnimation(.easeInOut(duration: 0.15)) { kind = move } } label: {
          VStack(spacing: 4) {
            Text(Theme.emoji[move] ?? "👋").font(.system(size: 21))
            Text(move.capitalized).font(.system(size: 10, weight: selected ? .semibold : .regular))
          }
          .frame(maxWidth: .infinity).padding(.vertical, 8)
          .foregroundStyle(selected ? Color.primary : Color.secondary)
          .background(selected ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.border : .clear))
          .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(BouncyButtonStyle()).accessibilityLabel("\(move.capitalized) move")
      }
    }
    .padding(3).background(Theme.inset, in: RoundedRectangle(cornerRadius: 10))
  }

  private var roomBar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Crew room").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        Spacer()
        if let code = relay.room {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
          } label: {
            Label("Copy code", systemImage: "doc.on.doc").font(.system(size: 10))
          }
          .buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
      }
      HStack(spacing: 8) {
        TextField(relay.room ?? "Room code", text: $room)
          .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
          .onSubmit { joinRoom() }
          .onChange(of: room) { _, value in
            let filtered = String(value.lowercased().filter {
              ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
            }.prefix(32))
            if filtered != value { room = filtered }
          }
        Button("Join", action: joinRoom).buttonStyle(.plain)
          .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
          .disabled(room.isEmpty || !relay.connected)
      }
      .padding(10).background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private var opponentList: some View {
    let inArena = relay.mode == Mode.arena.rawValue
    let rivals = inArena ? relay.rivals : []
    let strangers = relay.peers.filter { !rivals.contains($0) }
    return VStack(alignment: .leading, spacing: 8) {
      if rivals.isEmpty && strangers.isEmpty {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: inArena ? "person.badge.clock" : "person.2").foregroundStyle(.tertiary)
          VStack(alignment: .leading, spacing: 3) {
            Text(inArena ? (relay.onlineCount > 1 ? "Find your next opponent" : "No opponents yet") : "Waiting for your crew")
              .font(.system(size: 12, weight: .medium))
            Text(inArena
                 ? (relay.onlineCount > 1 ? "Shuffle the list, or send a random slap." : "Someone else needs to join before you can slap.")
                 : "Share the room code to bring your friends in.")
              .font(.system(size: 11)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if inArena && relay.onlineCount > 1 {
              Button("Find opponents", systemImage: "shuffle") { relay.shuffle() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
          }
          Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 3) {
            if !rivals.isEmpty {
              sectionTitle("Recent rivals")
              ForEach(rivals, id: \.self) { row($0) }
            }
            if !strangers.isEmpty {
              HStack {
                sectionTitle(inArena ? "Around you" : "Your crew")
                Spacer()
                if inArena {
                  Button { relay.shuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 11)).foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain).help("Find different opponents")
                  .accessibilityLabel("Shuffle opponents")
                }
              }
              ForEach(strangers, id: \.self) { row($0) }
            }
          }
          .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
          } action: { height in
            Task { @MainActor in peerListHeight = max(1, ceil(height)) }
          }
        }
        .frame(height: min(peerListHeight, 210))
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
      .padding(.top, 6).padding(.bottom, 4)
  }

  private func row(_ name: String) -> some View {
    PeerRow(name: name, kind: kind,
      onSlap: { relay.send(["t": "slap", "to": name, "kind": kind]) },
      onBlock: {
        relay.send(["t": "block", "name": name])
        withAnimation(.easeInOut(duration: 0.2)) {
          relay.peers.removeAll { $0 == name }
          relay.rivals.removeAll { $0 == name }
          if relay.lastHitFrom == name { relay.lastHitFrom = nil }
        }
      },
      onReport: { relay.send(["t": "report", "name": name]) })
      .disabled(!relay.connected)
  }

  private var activity: some View {
    DisclosureGroup(isExpanded: $showActivity) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(relay.feed) { item in
          HStack(spacing: 7) {
            Text(Theme.emoji[item.kind] ?? "👋").font(.system(size: 12))
            Text(item.incoming
                 ? "\(item.who) \((Theme.verb[item.kind] ?? "SLAPPED").lowercased()) you"
                 : "You \((Theme.verb[item.kind] ?? "SLAPPED").lowercased()) \(item.who)")
              .font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 0)
            Text(item.at, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
          }
        }
      }
      .padding(.top, 8)
    } label: {
      Text("Recent activity").font(.system(size: 11)).foregroundStyle(.secondary)
    }
    .tint(Theme.accent)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Text("\(relay.sent) sent").contentTransition(.numericText(value: Double(relay.sent)))
      Text("·").foregroundStyle(.tertiary)
      Text("\(relay.taken) received").contentTransition(.numericText(value: Double(relay.taken)))
      Spacer()
      Button(action: toggleEffects) {
        Label(fx.panicked ? "Resume" : "Pause effects", systemImage: fx.panicked ? "play" : "pause")
      }
      .buttonStyle(.plain).foregroundStyle(fx.panicked ? Theme.warning : Color.secondary)
      .help("Immediately pause or resume incoming sound and animation effects.")
    }
    .font(.system(size: 10)).foregroundStyle(.secondary)
    .animation(.easeOut(duration: 0.2), value: relay.sent)
    .animation(.easeOut(duration: 0.2), value: relay.taken)
  }

  private func toggleEffects() {
    withAnimation(.easeInOut(duration: 0.2)) {
      if fx.panicked { fx.unpanic() } else { fx.panic() }
    }
  }

  private func select(_ mode: Mode) {
    guard relay.mode != mode.rawValue, relay.connected else { return }
    relay.mode = mode.rawValue
    if mode == .crew {
      relay.send(["t": "set_mode", "mode": "crew", "room": room.isEmpty ? "lobby" : room])
    } else {
      relay.send(["t": "set_mode", "mode": mode.rawValue])
    }
  }

  private func joinRoom() {
    guard !room.isEmpty, relay.connected else { return }
    relay.send(["t": "set_mode", "mode": "crew", "room": room])
  }
}
