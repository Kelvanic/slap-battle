import AppKit
import Combine
import SwiftUI

/// The popup's size follows its content rather than SwiftUI's menu-window proposal.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
  private let model = AppModel()
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var hitObservation: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    model.updates.start()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    if let button = item.button {
      button.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Slap Battle")
      button.toolTip = "Slap Battle"
      button.target = self
      button.action = #selector(togglePanel)
    }

    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 360, height: 380)
    popover.contentViewController = NSHostingController(rootView: PopupContent(
      relay: model.relay,
      fx: model.fx,
      updates: model.updates,
      resize: { [weak self] size in
        guard let self, size.width > 0, size.height > 0 else { return }
        let rounded = NSSize(width: ceil(size.width), height: ceil(size.height))
        if self.popover.contentSize != rounded { self.popover.contentSize = rounded }
      }))

    hitObservation = model.relay.$taken.sink { [weak self] hits in
      self?.statusItem?.button?.image = NSImage(
        systemSymbolName: hits > 0 ? "hand.raised.fill" : "hand.raised",
        accessibilityDescription: "Slap Battle")
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showPanel()
    return true
  }

  @objc private func togglePanel() {
    if popover.isShown { popover.performClose(nil) }
    else { showPanel() }
  }

  private func showPanel() {
    guard let button = statusItem?.button else { return }
    NSApp.activate()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }
}

private struct PopupSize: PreferenceKey {
  static var defaultValue: CGSize { .zero }
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct PopupContent: View {
  @ObservedObject var relay: RelayClient
  @ObservedObject var fx: SlapFX
  @ObservedObject var updates: UpdateChecker
  let resize: @MainActor (CGSize) -> Void

  var body: some View {
    ContentView(relay: relay, fx: fx, updates: updates)
      .fixedSize(horizontal: false, vertical: true)
      .background(GeometryReader { geometry in
        Color.clear.preference(key: PopupSize.self, value: geometry.size)
      })
      .onPreferenceChange(PopupSize.self) { size in
        // AppKit resize must occur after SwiftUI's current layout transaction.
        Task { @MainActor in resize(size) }
      }
  }
}
