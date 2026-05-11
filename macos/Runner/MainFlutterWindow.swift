import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    isReleasedWhenClosed = false
    titleVisibility = .hidden

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    BridgeSenseController.shared.configure(binaryMessenger: flutterViewController.engine.binaryMessenger)
    BridgeSenseStatusItemController.shared.configure(mainWindow: self)

    super.awakeFromNib()
  }
}
