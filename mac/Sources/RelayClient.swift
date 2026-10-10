import Foundation

/// WebSocket client for the slap-battle relay. All inbound JSON is validated
/// field-by-field; unknown message types are ignored.
@MainActor
final class RelayClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
  @Published var name = "connecting…"
  @Published var mode = "private"
  @Published var peers: [String] = []
  @Published var kinds: [String] = ["slap"]
  @Published var connected = false
  var onSlapped: ((String, String) -> Void)?

  private var task: URLSessionWebSocketTask?
  private let url: URL

  init(url: URL = URL(string: "ws://localhost:8787")!) { self.url = url }

  func connect() {
    let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
    task = session.webSocketTask(with: url)
    task?.resume()
    connected = true
    receive()
  }

  func send(_ obj: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    task?.send(.data(data)) { _ in }
  }

  private func receive() {
    task?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let msg): self.handle(msg)
      case .failure: self.connected = false
      }
      if self.connected { self.receive() }
    }
  }

  private func text(of msg: URLSessionWebSocketTask.Message) -> String? {
    switch msg {
    case .string(let s): return s
    case .data(let d): return String(data: d, encoding: .utf8)
    @unknown default: return nil
    }
  }

  private func handle(_ msg: URLSessionWebSocketTask.Message) {
    guard let s = text(of: msg),
          let data = s.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let t = obj["t"] as? String else { return }
    switch t {
    case "hello":
      if let you = obj["you"] as? String { name = you }
      if let k = obj["slaps"] as? [String], !k.isEmpty { kinds = k }
    case "presence":
      if let n = obj["names"] as? [String] { peers = n }
      if let m = obj["mode"] as? String { mode = m }
      if let you = obj["you"] as? String { name = you }
    case "slapped":
      if let from = obj["from"] as? String, let kind = obj["kind"] as? String {
        onSlapped?(from, kind)
      }
    default: break
    }
  }

  nonisolated func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith c: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    Task { @MainActor in self.connected = false }
  }
}
