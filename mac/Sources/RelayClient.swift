import Foundation
import SwiftUI

struct FeedItem: Identifiable {
  let id = UUID()
  let incoming: Bool
  let who: String
  let kind: String
  let at: Date
}

/// WebSocket client for the slap-battle relay. Inbound JSON is validated field-by-field;
/// unknown message types are ignored. Reconnects automatically.
@MainActor
final class RelayClient: ObservableObject {
  @Published var name = "connecting…"
  @Published var mode = "private"
  @Published var room: String?
  @Published var peers: [String] = []
  @Published var kinds: [String] = ["slap"]
  @Published var connected = false
  @Published var sent = 0
  @Published var taken = 0
  @Published var lastHitFrom: String?
  @Published var feed: [FeedItem] = []
  var onSlapped: (@MainActor (String, String) -> Void)?

  private let session = URLSession(configuration: .ephemeral)
  private var task: URLSessionWebSocketTask?
  private let url: URL

  init(url: URL = URL(string: ProcessInfo.processInfo.environment["SLAP_RELAY_URL"]
    ?? "ws://lprjtzxw20a1qwtnx4yamduu.167.233.108.153.sslip.io")!) { self.url = url }

  func connect() {
    let t = session.webSocketTask(with: url)
    task = t
    t.resume()
    Task { await receiveLoop(t) }
  }

  func send(_ obj: [String: String]) {
    guard let t = task,
          let data = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: data, encoding: .utf8) else { return }
    Task { try? await t.send(.string(s)) }
  }

  private func receiveLoop(_ t: URLSessionWebSocketTask) async {
    while true {
      guard let msg = try? await t.receive() else { break }
      handle(msg)
    }
    guard task === t else { return }
    withAnimation { connected = false }
    try? await Task.sleep(for: .seconds(2))
    if task === t { connect() }
  }

  private func handle(_ msg: URLSessionWebSocketTask.Message) {
    let raw: Data? = switch msg {
    case .string(let s): s.data(using: .utf8)
    case .data(let d): d
    @unknown default: nil
    }
    guard let raw,
          let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
          let t = obj["t"] as? String else { return }

    switch t {
    case "hello":
      withAnimation(.spring) {
        connected = true
        if let you = obj["you"] as? String { name = you }
        if let k = obj["slaps"] as? [String], !k.isEmpty { kinds = k }
        // Server always starts us private after (re)connect.
        mode = "private"; room = nil; peers = []
      }
    case "presence":
      withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
        if let n = obj["names"] as? [String] { peers = n }
        if let m = obj["mode"] as? String { mode = m }
        if let you = obj["you"] as? String { name = you }
        room = obj["room"] as? String
      }
    case "slapped":
      guard let from = obj["from"] as? String, let kind = obj["kind"] as? String else { return }
      withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
        taken += 1
        lastHitFrom = from
        push(FeedItem(incoming: true, who: from, kind: kind, at: Date()))
      }
      onSlapped?(from, kind)
    case "slap_ok":
      guard let to = obj["to"] as? String, let kind = obj["kind"] as? String else { return }
      withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
        sent += 1
        push(FeedItem(incoming: false, who: to, kind: kind, at: Date()))
      }
    default:
      break
    }
  }

  private func push(_ item: FeedItem) {
    feed.insert(item, at: 0)
    if feed.count > 5 { feed.removeLast(feed.count - 5) }
  }
}
