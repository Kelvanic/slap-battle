import SwiftUI

@main
struct SlapBattleApp: App {
  @StateObject private var relay = RelayClient()
  @StateObject private var fx = SlapFX()
  @State private var lastHit: String?

  var body: some Scene {
    MenuBarExtra("SlapBattle", systemImage: "hand.raised") {
      ContentView(relay: relay, fx: fx, lastHit: $lastHit)
        .onAppear {
          relay.connect()
          relay.onSlapped = { from, kind in
            lastHit = from
            fx.fire(kind: from == lastHit ? kind : kind, from: from)
          }
        }
    }
    .menuBarExtraStyle(.window)
  }
}

struct ContentView: View {
  @ObservedObject var relay: RelayClient
  @ObservedObject var fx: SlapFX
  @Binding var lastHit: String?
  @State private var room = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(relay.name).font(.headline)
        Spacer()
        Button("🎲") { relay.send(["t": "regen_name"]) }.help("New random name")
      }
      Picker("Mode", selection: modeBinding) {
        Text("🔒 Private").tag("private")
        Text("👥 Crew").tag("crew")
        Text("⚔️ Arena").tag("arena")
      }.pickerStyle(.segmented)
      if relay.mode == "crew" && relay.peers.isEmpty {
        HStack {
          TextField("room-code", text: $room)
          Button("Join") { relay.send(["t": "set_mode", "mode": "crew", "room": room]) }
        }
      }
      if fx.panicked {
        Button("▶ Resume (unpanic)") { fx.unpanic() }
      } else {
        Button("🛑 PANIC — mute everything") { fx.panic() }
      }
      Divider()
      if let h = lastHit {
        Button("↩️ Slap \(h) back!") { relay.send(["t": "slap", "to": h, "kind": "slap"]) }
      }
      Text("Online (\(relay.peers.count))").font(.caption).foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading) {
          ForEach(relay.peers, id: \.self) { peer in
            HStack {
              Text(peer).lineLimit(1)
              Spacer()
              ForEach(relay.kinds.prefix(3), id: \.self) { k in
                Button(k) { relay.send(["t": "slap", "to": peer, "kind": k]) }
                  .buttonStyle(.borderless)
              }
              Button("🚫") { relay.send(["t": "block", "name": peer]) }.help("Block")
            }
          }
        }
      }.frame(minHeight: 120)
      Text(relay.connected ? "connected" : "disconnected")
        .font(.caption2).foregroundStyle(relay.connected ? .green : .red)
    }
    .padding()
    .frame(width: 340)
  }

  private var modeBinding: Binding<String> {
    Binding(
      get: { relay.mode },
      set: { m in
        if m == "crew" {
          relay.send(["t": "set_mode", "mode": "crew", "room": room.isEmpty ? "lobby" : room])
        } else {
          relay.send(["t": "set_mode", "mode": m])
        }
      }
    )
  }
}
