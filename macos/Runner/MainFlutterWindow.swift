import Cocoa
import FlutterMacOS
import WidgetKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWidgetChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Receives the current week from Dart and stores it where the desktop
  /// widget can read it (the shared app group container).
  private func registerWidgetChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "register/widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "saveWeek", let json = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let group = Bundle.main.object(forInfoDictionaryKey: "RegisterAppGroup") as? String,
        let container = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: group)
      else {
        result(FlutterError(code: "no_app_group", message: "App group not available", details: nil))
        return
      }
      do {
        try json.write(
          to: container.appendingPathComponent("week.json"), atomically: true, encoding: .utf8)
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      } catch {
        result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
