import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    BridgeSenseStatusItemController.shared.configure(
      mainWindow: NSApp.windows.first { $0 is MainFlutterWindow } ?? NSApp.mainWindow
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    BridgeSenseStatusItemController.shared.showMainWindow()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

final class BridgeSenseStatusItemController: NSObject {
  static let shared = BridgeSenseStatusItemController()

  private var statusItem: NSStatusItem?
  private weak var mainWindow: NSWindow?

  func configure(mainWindow: NSWindow?) {
    self.mainWindow = mainWindow ?? self.mainWindow

    if statusItem != nil {
      return
    }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item

    guard let button = item.button else {
      return
    }

    item.isVisible = true
    button.image = statusBarImage()
    button.imagePosition = .imageOnly
    button.toolTip = "BridgeSense"

    let menu = NSMenu()
    let showItem = NSMenuItem(
      title: "Show BridgeSense",
      action: #selector(showBridgeSense),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit BridgeSense",
      action: #selector(quitBridgeSense),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
  }

  private func statusBarImage() -> NSImage {
    if #available(macOS 11.0, *),
      let image = NSImage(
        systemSymbolName: "gamecontroller.fill",
        accessibilityDescription: "BridgeSense"
      ) {
      image.isTemplate = true
      return image
    }

    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 2, y: 7, width: 14, height: 4), xRadius: 2, yRadius: 2).fill()
    NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 4, height: 10), xRadius: 1.5, yRadius: 1.5).fill()
    NSBezierPath(roundedRect: NSRect(x: 10, y: 4, width: 4, height: 10), xRadius: 1.5, yRadius: 1.5).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 5.25, y: 8, width: 1.5, height: 1.5)).fill()
    NSBezierPath(ovalIn: NSRect(x: 11.25, y: 8, width: 1.5, height: 1.5)).fill()
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  @objc private func showBridgeSense() {
    showMainWindow()
  }

  @objc private func quitBridgeSense() {
    NSApp.terminate(nil)
  }

  func showMainWindow() {
    let window = mainWindow ?? NSApp.windows.first { $0 is MainFlutterWindow } ?? NSApp.mainWindow
    guard let window else {
      return
    }

    mainWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
