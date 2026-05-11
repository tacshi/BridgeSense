import ApplicationServices
import Cocoa
import CoreHaptics
import FlutterMacOS
import GameController
import IOKit.hid

final class BridgeSenseController: NSObject, FlutterStreamHandler {
  static let shared = BridgeSenseController()

  private let mappingsKey = "BridgeSenseMappingsV2"
  private let settingsKey = "BridgeSenseSettingsV1"
  private let enabledKey = "BridgeSenseEnabledV1"
  private let buttonThreshold = 0.55
  private let accessibilityRefreshInterval = 1.0

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var pollTimer: Timer?
  private var accessibilityTimer: Timer?
  private var currentController: GCController?
  private var previousPressed: [String: Bool] = [:]
  private var inputValues: [String: Double] = [:]
  private var accessibilityTrustedState = false
  private var lastAction = ""
  private var lastEmit = Date.distantPast
  private var hapticEngine: CHHapticEngine?
  private var previousTouchpadPoint: CGPoint?
  private var rawTouchpadSample = TouchpadSample.inactive
  private let rawTouchpadReader = RawDualSenseTouchpadReader()

  private var mappings: [BridgeMapping] = BridgeMapping.defaults
  private var settings = BridgeSettings.defaults
  private var bridgeEnabled = true

  private override init() {
    super.init()
    rawTouchpadReader.onSample = { [weak self] sample in
      self?.handleRawTouchpadSample(sample)
    }
    loadState()
    accessibilityTrustedState = readAccessibilityTrusted(prompt: false)
    observeControllers()
    rawTouchpadReader.start()
    startAccessibilityMonitoring()
    startPolling()
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "bridge_sense/control",
      binaryMessenger: binaryMessenger
    )
    eventChannel = FlutterEventChannel(
      name: "bridge_sense/events",
      binaryMessenger: binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    eventChannel?.setStreamHandler(self)
    refreshController(reason: "Ready")
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    refreshAccessibilityTrust(emitOnChange: false)
    emitSnapshot(force: true)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func observeControllers() {
    if #available(macOS 11.3, *) {
      GCController.shouldMonitorBackgroundEvents = true
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(controllerDidChange(_:)),
      name: .GCControllerDidConnect,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(controllerDidChange(_:)),
      name: .GCControllerDidDisconnect,
      object: nil
    )

    GCController.startWirelessControllerDiscovery(completionHandler: nil)
  }

  @objc private func controllerDidChange(_ notification: Notification) {
    refreshController(reason: "Controller updated")
  }

  private func refreshController(reason: String) {
    let candidates = GCController.controllers().filter { $0.extendedGamepad != nil }
    let preferred = candidates.first { controller in
      controller.vendorName?.localizedCaseInsensitiveContains("DualSense") == true
        || controller.productCategory.localizedCaseInsensitiveContains("DualSense")
    }

    if let preferred {
      currentController = preferred
    } else if #available(macOS 11.0, *),
      let current = GCController.current,
      current.extendedGamepad != nil {
      currentController = current
    } else {
      currentController = candidates.first
    }

    previousPressed.removeAll()
    previousTouchpadPoint = nil
    rawTouchpadSample = .inactive
    inputValues = readInputs()
    lastAction = currentController == nil ? "Waiting for controller" : reason
    emitSnapshot(force: true)
  }

  private func startPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      self?.poll()
    }
    RunLoop.main.add(pollTimer!, forMode: .common)
  }

  private func startAccessibilityMonitoring() {
    accessibilityTimer?.invalidate()
    accessibilityTimer = Timer.scheduledTimer(
      withTimeInterval: accessibilityRefreshInterval,
      repeats: true
    ) { [weak self] _ in
      self?.refreshAccessibilityTrust()
    }
    RunLoop.main.add(accessibilityTimer!, forMode: .common)
  }

  private func poll() {
    guard currentController?.extendedGamepad != nil else {
      emitSnapshot()
      return
    }

    inputValues = readInputs()

    if bridgeEnabled {
      applyContinuousMappings()
      applyButtonMappings()
    }

    emitSnapshot()
  }

  private func applyContinuousMappings() {
    guard accessibilityTrustedState else {
      return
    }

    for mapping in mappings where isContinuousMapping(mapping.id) {
      if mapping.id == "touchpadMotion" {
        applyTouchpadMapping(mapping)
        continue
      }

      let xKey = mapping.id == "leftStick" ? "leftStickX" : "rightStickX"
      let yKey = mapping.id == "leftStick" ? "leftStickY" : "rightStickY"
      let x = filteredAxis(inputValues[xKey] ?? 0)
      let y = filteredAxis(inputValues[yKey] ?? 0)

      switch mapping.action {
      case .cursor:
        if abs(x) > 0 || abs(y) > 0 {
          moveCursor(x: x, y: y)
        }
      case .scroll:
        if abs(x) > 0 || abs(y) > 0 {
          scroll(x: x, y: y)
        }
      default:
        break
      }
    }
  }

  private func applyButtonMappings() {
    let buttonValues = inputValues.filter { key, _ in
      !key.hasSuffix("X") && !key.hasSuffix("Y")
    }

    for mapping in mappings where !isContinuousMapping(mapping.id) {
      let value = buttonValues[mapping.id] ?? 0
      let pressed = value >= buttonThreshold
      let wasPressed = previousPressed[mapping.id] ?? false
      applyAdaptiveTriggerMapping(mapping, pressed: pressed, wasPressed: wasPressed)
      if pressed && !wasPressed {
        perform(mapping: mapping)
      }
      previousPressed[mapping.id] = pressed
    }
  }

  private func syncPreviousPressedWithCurrentInputs() {
    guard currentController?.extendedGamepad != nil else {
      previousPressed.removeAll()
      return
    }

    inputValues = readInputs()
    for mapping in mappings where !isContinuousMapping(mapping.id) {
      previousPressed[mapping.id] = (inputValues[mapping.id] ?? 0) >= buttonThreshold
    }
  }

  private func isContinuousMapping(_ id: String) -> Bool {
    id == "leftStick" || id == "rightStick" || id == "touchpadMotion"
  }

  private func applyAdaptiveTriggerMapping(
    _ mapping: BridgeMapping,
    pressed: Bool,
    wasPressed: Bool
  ) {
    guard let side = adaptiveTriggerSide(for: mapping.id) else {
      return
    }
    guard mapping.vibrate else {
      if pressed != wasPressed, !pressed {
        resetAdaptiveTriggers(sides: side)
      }
      return
    }
    guard pressed != wasPressed else {
      return
    }

    if pressed {
      configureAdaptiveTriggers(
        style: adaptiveTriggerStyle(for: mapping),
        sides: side,
        resetAfterDelay: false
      )
    } else {
      resetAdaptiveTriggers(sides: side)
    }
  }

  private func adaptiveTriggerSide(for id: String) -> DualSenseTriggerSides? {
    switch id {
    case "l2":
      return .left
    case "r2":
      return .right
    default:
      return nil
    }
  }

  private func adaptiveTriggerStyle(for mapping: BridgeMapping) -> String {
    if mapping.hapticStyle != "pulse" {
      return mapping.hapticStyle
    }
    return mapping.id == "r2" ? "gunshot" : "engine"
  }

  private func applyTouchpadMapping(_ mapping: BridgeMapping) {
    applyTouchpadSample(
      TouchpadSample(
        point: CGPoint(
          x: inputValues["touchpadX"] ?? 0,
          y: inputValues["touchpadY"] ?? 0
        ),
        button: inputValues["touchpad"] ?? 0,
        active: (inputValues["touchpadActive"] ?? 0) >= 0.5
      ),
      mapping: mapping
    )
  }

  private func applyTouchpadSample(_ sample: TouchpadSample, mapping: BridgeMapping) {
    guard sample.active else {
      previousTouchpadPoint = nil
      return
    }

    let point = sample.point
    defer { previousTouchpadPoint = point }

    guard let previousTouchpadPoint else {
      return
    }

    let dx = Double(point.x - previousTouchpadPoint.x)
    let dy = Double(point.y - previousTouchpadPoint.y)
    guard abs(dx) > 0.002 || abs(dy) > 0.002 else {
      return
    }
    guard abs(dx) <= 0.45 && abs(dy) <= 0.45 else {
      return
    }

    switch mapping.action {
    case .cursor:
      let scale = settings.pointerSpeed * 8
      moveCursorBy(dx: CGFloat(dx * scale), dy: CGFloat(-dy * scale))
    case .scroll:
      let scale = settings.scrollSpeed * 10
      scrollDelta(
        horizontal: Int32((dx * scale).rounded()),
        vertical: Int32((dy * scale).rounded())
      )
    default:
      break
    }
  }

  private func handleRawTouchpadSample(_ sample: TouchpadSample) {
    rawTouchpadSample = sample
    inputValues["touchpad"] = sample.button
    inputValues["touchpadX"] = sample.active ? Double(sample.point.x) : 0
    inputValues["touchpadY"] = sample.active ? Double(sample.point.y) : 0
    inputValues["touchpadActive"] = sample.active ? 1 : 0

    guard bridgeEnabled,
      accessibilityTrustedState,
      let mapping = mappings.first(where: { $0.id == "touchpadMotion" }) else {
      emitSnapshot()
      return
    }

    applyTouchpadSample(sample, mapping: mapping)
    emitSnapshot()
  }

  private func perform(mapping: BridgeMapping) {
    var actionDescription: String?

    switch mapping.action {
    case .key:
      guard accessibilityTrustedState else {
        actionDescription = "Accessibility permission required"
        break
      }
      guard let keyCode = mapping.keyCode else {
        break
      }
      postKeyTap(keyCode: keyCode, modifiers: mapping.modifiers)
      let purpose = mapping.label.isEmpty ? mapping.controlLabel : mapping.label
      actionDescription = "\(mapping.controlLabel): \(purpose) -> \(mapping.keyLabel)"
    case .mouseClick:
      guard accessibilityTrustedState else {
        actionDescription = "Accessibility permission required"
        break
      }
      postMouseClick(button: mapping.mouseButton)
      actionDescription = "\(mapping.controlLabel): \(mapping.mouseButton.actionDescription)"
    default:
      break
    }

    if mapping.vibrate || mapping.action == .haptic {
      do {
        try playHaptic(style: mapping.hapticStyle)
        let hapticDescription = "vibration \(mapping.hapticStyle)"
        if let existingDescription = actionDescription {
          actionDescription = "\(existingDescription); \(hapticDescription)"
        } else {
          actionDescription = "\(mapping.controlLabel): \(hapticDescription)"
        }
      } catch {
        actionDescription = actionDescription ?? "Vibration unavailable"
      }
    }

    if let actionDescription {
      lastAction = actionDescription
    }
    emitSnapshot(force: true)
  }

  private func filteredAxis(_ value: Double) -> Double {
    abs(value) < settings.deadZone ? 0 : value
  }

  private func moveCursor(x: Double, y: Double) {
    let dx = CGFloat(x * settings.pointerSpeed)
    let dy = CGFloat(-y * settings.pointerSpeed)
    moveCursorBy(dx: dx, dy: dy)
  }

  private func moveCursorBy(dx: CGFloat, dy: CGFloat) {
    guard let event = CGEvent(source: nil) else {
      return
    }

    let current = event.location
    let next = CGPoint(x: current.x + dx, y: current.y + dy)
    CGEvent(
      mouseEventSource: nil,
      mouseType: .mouseMoved,
      mouseCursorPosition: next,
      mouseButton: .left
    )?.post(tap: .cghidEventTap)
  }

  private func scroll(x: Double, y: Double) {
    let horizontal = Int32((x * settings.scrollSpeed).rounded())
    let vertical = Int32((y * settings.scrollSpeed).rounded())
    scrollDelta(horizontal: horizontal, vertical: vertical)
  }

  private func scrollDelta(horizontal: Int32, vertical: Int32) {
    guard horizontal != 0 || vertical != 0 else {
      return
    }
    CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: vertical,
      wheel2: horizontal,
      wheel3: 0
    )?.post(tap: .cghidEventTap)
  }

  private func postMouseClick(button: MouseButton) {
    guard let event = CGEvent(source: nil) else {
      return
    }
    let point = event.location
    CGEvent(
      mouseEventSource: nil,
      mouseType: button.downEvent,
      mouseCursorPosition: point,
      mouseButton: button.cgButton
    )?.post(tap: .cghidEventTap)
    CGEvent(
      mouseEventSource: nil,
      mouseType: button.upEvent,
      mouseCursorPosition: point,
      mouseButton: button.cgButton
    )?.post(tap: .cghidEventTap)
  }

  private func postKeyTap(keyCode: UInt16, modifiers: [String]) {
    let source = CGEventSource(stateID: .hidSystemState)
    let flags = eventFlags(from: modifiers)
    let keyDown = CGEvent(
      keyboardEventSource: source,
      virtualKey: keyCode,
      keyDown: true
    )
    keyDown?.flags = flags
    keyDown?.post(tap: .cghidEventTap)

    let keyUp = CGEvent(
      keyboardEventSource: source,
      virtualKey: keyCode,
      keyDown: false
    )
    keyUp?.flags = flags
    keyUp?.post(tap: .cghidEventTap)
  }

  private func eventFlags(from modifiers: [String]) -> CGEventFlags {
    var flags = CGEventFlags()
    for modifier in modifiers {
      switch modifier {
      case "command":
        flags.insert(.maskCommand)
      case "shift":
        flags.insert(.maskShift)
      case "option":
        flags.insert(.maskAlternate)
      case "control":
        flags.insert(.maskControl)
      default:
        break
      }
    }
    return flags
  }

  private func readInputs() -> [String: Double] {
    guard let gamepad = currentController?.extendedGamepad else {
      return [:]
    }

    var values: [String: Double] = [
      "leftStickX": Double(gamepad.leftThumbstick.xAxis.value),
      "leftStickY": Double(gamepad.leftThumbstick.yAxis.value),
      "rightStickX": Double(gamepad.rightThumbstick.xAxis.value),
      "rightStickY": Double(gamepad.rightThumbstick.yAxis.value),
      "dpadX": Double(gamepad.dpad.xAxis.value),
      "dpadY": Double(gamepad.dpad.yAxis.value),
      "dpadUp": Double(gamepad.dpad.up.value),
      "dpadDown": Double(gamepad.dpad.down.value),
      "dpadLeft": Double(gamepad.dpad.left.value),
      "dpadRight": Double(gamepad.dpad.right.value),
      "cross": Double(gamepad.buttonA.value),
      "circle": Double(gamepad.buttonB.value),
      "square": Double(gamepad.buttonX.value),
      "triangle": Double(gamepad.buttonY.value),
      "l1": Double(gamepad.leftShoulder.value),
      "r1": Double(gamepad.rightShoulder.value),
      "l2": Double(gamepad.leftTrigger.value),
      "r2": Double(gamepad.rightTrigger.value),
      "menu": Double(gamepad.buttonMenu.value),
      "options": Double(gamepad.buttonOptions?.value ?? 0),
      "leftStickButton": Double(gamepad.leftThumbstickButton?.value ?? 0),
      "rightStickButton": Double(gamepad.rightThumbstickButton?.value ?? 0),
      "home": 0,
      "touchpad": 0,
      "touchpadX": 0,
      "touchpadY": 0,
      "touchpadActive": 0,
    ]

    if #available(macOS 11.0, *) {
      values["home"] = Double(gamepad.buttonHome?.value ?? 0)
    }

    let touchpadSample = readTouchpadSample(gamepad: gamepad)
    values["touchpad"] = touchpadSample.button
    values["touchpadX"] = touchpadSample.active ? Double(touchpadSample.point.x) : 0
    values["touchpadY"] = touchpadSample.active ? Double(touchpadSample.point.y) : 0
    values["touchpadActive"] = touchpadSample.active ? 1 : 0

    return values
  }

  private func readTouchpadSample(gamepad: GCExtendedGamepad) -> TouchpadSample {
    if rawTouchpadSample.active {
      return rawTouchpadSample
    }

    if #available(macOS 11.0, *),
      let touchpad = currentControllerTouchpad() {
      let active = touchpad.touchState == .down || touchpad.touchState == .moving
      if active {
        return TouchpadSample(
          point: CGPoint(
            x: Double(touchpad.touchSurface.xAxis.value),
            y: Double(touchpad.touchSurface.yAxis.value)
          ),
          button: Double(touchpad.button.value),
          active: true
        )
      }
    }

    if #available(macOS 11.3, *),
      let dualSense = gamepad as? GCDualSenseGamepad {
      return directionalTouchpadSample(
        dpad: dualSense.touchpadPrimary,
        button: dualSense.touchpadButton
      )
    }

    if #available(macOS 11.0, *),
      let dualShock = gamepad as? GCDualShockGamepad {
      return directionalTouchpadSample(
        dpad: dualShock.touchpadPrimary,
        button: dualShock.touchpadButton
      )
    }

    return .inactive
  }

  @available(macOS 11.0, *)
  private func currentControllerTouchpad() -> GCControllerTouchpad? {
    guard let currentController else {
      return nil
    }
    let touchpads = currentController.physicalInputProfile.touchpads
    return touchpads.values.first { touchpad in
      touchpad.touchState == .down || touchpad.touchState == .moving
    } ?? touchpads[GCInputDualShockTouchpadOne] ?? touchpads.values.first
  }

  private func directionalTouchpadSample(
    dpad: GCControllerDirectionPad,
    button: GCControllerButtonInput
  ) -> TouchpadSample {
    let point = CGPoint(
      x: Double(dpad.xAxis.value),
      y: Double(dpad.yAxis.value)
    )
    let buttonValue = Double(button.value)

    if isDirectionalTouchpadResting(point) {
      return .inactive(button: buttonValue)
    }

    return TouchpadSample(
      point: point,
      button: buttonValue,
      active: true
    )
  }

  private func isDirectionalTouchpadResting(_ point: CGPoint) -> Bool {
    abs(Double(point.x) + 1) < 0.001 && abs(Double(point.y) - 1) < 0.001
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSnapshot":
      refreshAccessibilityTrust()
      result(snapshot())
    case "setBridgeEnabled":
      bridgeEnabled = (call.arguments as? Bool) ?? true
      if !bridgeEnabled {
        resetAdaptiveTriggers()
        previousPressed.removeAll()
      }
      UserDefaults.standard.set(bridgeEnabled, forKey: enabledKey)
      emitSnapshot(force: true)
      result(nil)
    case "setMappings":
      guard let rawMappings = call.arguments as? [[String: Any]] else {
        result(FlutterError(code: "bad_args", message: "Expected mappings", details: nil))
        return
      }
      mappings = normalizeMappings(rawMappings.compactMap(BridgeMapping.init(dictionary:)))
      resetDisabledAdaptiveTriggers()
      saveMappings()
      emitSnapshot(force: true)
      result(nil)
    case "setSettings":
      settings = BridgeSettings(dictionary: call.arguments as? [String: Any]) ?? .defaults
      saveSettings()
      emitSnapshot(force: true)
      result(nil)
    case "resetMappings":
      mappings = BridgeMapping.defaults
      resetAdaptiveTriggers()
      saveMappings()
      emitSnapshot(force: true)
      result(snapshot())
    case "requestAccessibility":
      let trusted = refreshAccessibilityTrust(prompt: true, emitOnChange: false)
      lastAction = trusted ? "Accessibility trusted" : "Accessibility requested"
      emitSnapshot(force: true)
      result(["trusted": trusted])
    case "playHaptic":
      let style = (call.arguments as? [String: Any])?["style"] as? String ?? "pulse"
      do {
        try playHaptic(style: style)
        lastAction = "Vibration: \(style)"
        emitSnapshot(force: true)
        result(nil)
      } catch {
        result(FlutterError(code: "haptics_unavailable", message: error.localizedDescription, details: nil))
      }
    case "stopHaptics":
      stopHaptics()
      lastAction = "Vibration stopped"
      emitSnapshot(force: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func loadState() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: enabledKey) != nil {
      bridgeEnabled = defaults.bool(forKey: enabledKey)
    }

    if let raw = defaults.array(forKey: mappingsKey) {
      let loaded = raw.compactMap { item -> BridgeMapping? in
        guard let dictionary = item as? [String: Any] else {
          return nil
        }
        return BridgeMapping(dictionary: dictionary)
      }
      if !loaded.isEmpty {
        mappings = normalizeMappings(loaded)
      }
    }

    if let dictionary = defaults.dictionary(forKey: settingsKey),
      let loaded = BridgeSettings(dictionary: dictionary) {
      settings = loaded
    }
  }

  private func saveMappings() {
    UserDefaults.standard.set(
      mappings.map { $0.dictionary(includeNil: false) },
      forKey: mappingsKey
    )
  }

  private func saveSettings() {
    UserDefaults.standard.set(settings.dictionary, forKey: settingsKey)
  }

  private func normalizeMappings(_ loaded: [BridgeMapping]) -> [BridgeMapping] {
    BridgeMapping.defaults.map { fallback in
      guard let existing = loaded.first(where: { $0.id == fallback.id }) else {
        return fallback
      }
      if existing.id == "touchpad" && existing.action == .none && existing.label.isEmpty {
        return fallback
      }
      return existing
    }
  }

  private func snapshot() -> [String: Any] {
    let controller = currentController
    let vendorName = controller?.vendorName ?? "No controller"
    let category = controller?.productCategory ?? "Unknown"
    return [
      "connected": controller != nil,
      "controllerName": vendorName,
      "productCategory": category,
      "isDualSense": isDualSense,
      "hapticsAvailable": hapticsAvailable,
      "adaptiveTriggersAvailable": adaptiveTriggersAvailable,
      "accessibilityTrusted": accessibilityTrustedState,
      "bridgeEnabled": bridgeEnabled,
      "lastAction": lastAction,
      "inputs": inputValues,
      "mappings": mappings.map { $0.dictionary(includeNil: true) },
      "settings": settings.dictionary,
    ]
  }

  private func emitSnapshot(force: Bool = false) {
    guard let eventSink else {
      return
    }
    let now = Date()
    if !force && now.timeIntervalSince(lastEmit) < 0.08 {
      return
    }
    lastEmit = now
    eventSink(snapshot())
  }

  private var isDualSense: Bool {
    if #available(macOS 11.3, *) {
      if currentController?.extendedGamepad is GCDualSenseGamepad {
        return true
      }
    }
    return rawTouchpadReader.hasDualSenseDevice
  }

  private var hapticsAvailable: Bool {
    guard #available(macOS 11.0, *) else {
      return false
    }
    return currentController?.haptics != nil
  }

  private var adaptiveTriggersAvailable: Bool {
    if rawTouchpadReader.hasDualSenseDevice {
      return true
    }
    guard #available(macOS 11.3, *) else {
      return false
    }
    return currentController?.extendedGamepad is GCDualSenseGamepad
  }

  @discardableResult
  private func refreshAccessibilityTrust(prompt: Bool = false, emitOnChange: Bool = true) -> Bool {
    let trusted = readAccessibilityTrusted(prompt: prompt)
    guard trusted != accessibilityTrustedState else {
      return trusted
    }

    accessibilityTrustedState = trusted
    if trusted {
      syncPreviousPressedWithCurrentInputs()
    } else {
      previousPressed.removeAll()
      resetAdaptiveTriggers()
    }
    lastAction = trusted ? "Accessibility trusted" : "Accessibility revoked"
    if emitOnChange {
      emitSnapshot(force: true)
    }
    return trusted
  }

  private func readAccessibilityTrusted(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  private func playHaptic(style: String) throws {
    guard #available(macOS 11.0, *) else {
      throw BridgeSenseError.hapticsUnavailable
    }
    guard let haptics = currentController?.haptics,
      let engine = hapticEngine ?? haptics.createEngine(withLocality: .default) else {
      throw BridgeSenseError.hapticsUnavailable
    }

    hapticEngine = engine
    try engine.start()
    try playPattern(style: style, engine: engine)
  }

  @available(macOS 11.0, *)
  private func playPattern(style: String, engine: CHHapticEngine) throws {
    let events: [CHHapticEvent]
    switch style {
    case "engine":
      events = [
        continuousEvent(intensity: 0.36, sharpness: 0.18, time: 0, duration: 1.4),
        transientEvent(intensity: 0.5, sharpness: 0.2, time: 0.18),
        transientEvent(intensity: 0.48, sharpness: 0.2, time: 0.42),
        transientEvent(intensity: 0.54, sharpness: 0.24, time: 0.7),
        transientEvent(intensity: 0.5, sharpness: 0.2, time: 1.0),
      ]
    case "gunshot":
      events = [
        transientEvent(intensity: 1.0, sharpness: 0.92, time: 0),
        transientEvent(intensity: 0.5, sharpness: 0.35, time: 0.08),
      ]
    default:
      events = [
        transientEvent(intensity: 0.68, sharpness: 0.45, time: 0),
      ]
    }

    let pattern = try CHHapticPattern(events: events, parameters: [])
    let player = try engine.makePlayer(with: pattern)
    try player.start(atTime: CHHapticTimeImmediate)
  }

  @available(macOS 11.0, *)
  private func transientEvent(intensity: Float, sharpness: Float, time: TimeInterval) -> CHHapticEvent {
    CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: time
    )
  }

  @available(macOS 11.0, *)
  private func continuousEvent(
    intensity: Float,
    sharpness: Float,
    time: TimeInterval,
    duration: TimeInterval
  ) -> CHHapticEvent {
    CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: time,
      duration: duration
    )
  }

  private func stopHaptics() {
    hapticEngine?.stop(completionHandler: nil)
    hapticEngine = nil
    resetAdaptiveTriggers()
  }

  private func configureAdaptiveTriggers(
    style: String,
    sides requestedSides: DualSenseTriggerSides? = nil,
    resetAfterDelay: Bool = true
  ) {
    let effect = DualSenseAdaptiveTriggerEffect.effect(
      forHapticStyle: style,
      sides: requestedSides
    )
    rawTouchpadReader.setAdaptiveTriggers(effect)

    if #available(macOS 11.3, *),
      let dualSense = currentController?.extendedGamepad as? GCDualSenseGamepad {
      configureGameControllerAdaptiveTriggers(
        dualSense,
        style: style,
        sides: effect.sides
      )
    }

    guard resetAfterDelay else {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      self?.resetAdaptiveTriggers(sides: effect.sides)
    }
  }

  @available(macOS 11.3, *)
  private func configureGameControllerAdaptiveTriggers(
    _ dualSense: GCDualSenseGamepad,
    style: String,
    sides: DualSenseTriggerSides
  ) {
    if sides.contains(.left) {
      switch style {
      case "engine":
        dualSense.leftTrigger.setModeFeedbackWithStartPosition(0.12, resistiveStrength: 0.35)
      case "gunshot":
        dualSense.leftTrigger.setModeWeaponWithStartPosition(
          0.18,
          endPosition: 0.78,
          resistiveStrength: 0.95
        )
      default:
        dualSense.leftTrigger.setModeVibrationWithStartPosition(
          0.12,
          amplitude: 0.45,
          frequency: 0.5
        )
      }
    }

    if sides.contains(.right) {
      switch style {
      case "engine":
        dualSense.rightTrigger.setModeFeedbackWithStartPosition(0.12, resistiveStrength: 0.35)
      case "gunshot":
        dualSense.rightTrigger.setModeWeaponWithStartPosition(
          0.18,
          endPosition: 0.78,
          resistiveStrength: 0.95
        )
      default:
        dualSense.rightTrigger.setModeVibrationWithStartPosition(
          0.12,
          amplitude: 0.45,
          frequency: 0.5
        )
      }
    }
  }

  private func resetAdaptiveTriggers(sides: DualSenseTriggerSides = .both) {
    rawTouchpadReader.setAdaptiveTriggers(.off(sides: sides))
    guard #available(macOS 11.3, *),
      let dualSense = currentController?.extendedGamepad as? GCDualSenseGamepad else {
      return
    }
    if sides.contains(.left) {
      dualSense.leftTrigger.setModeOff()
    }
    if sides.contains(.right) {
      dualSense.rightTrigger.setModeOff()
    }
  }

  private func resetDisabledAdaptiveTriggers() {
    for mapping in mappings where !mapping.vibrate {
      guard let side = adaptiveTriggerSide(for: mapping.id) else {
        continue
      }
      resetAdaptiveTriggers(sides: side)
    }
  }
}

private final class RawDualSenseTouchpadReader {
  private static let vendorID = 0x054c
  private static let productIDs = [0x0ce6, 0x0df2]
  private static let touchpadWidth = 1920.0
  private static let touchpadHeight = 1080.0
  private static let outputReportIDUSB = 0x02
  private static let outputReportIDBluetooth = 0x31
  private static let outputReportSizeUSB = 48
  private static let outputReportSizeBluetooth = 78
  private static let outputReportTagBluetooth: UInt8 = 0x10
  private static let outputReportCRCSeed: UInt8 = 0xa2

  var onSample: ((TouchpadSample) -> Void)?
  var hasDualSenseDevice: Bool {
    devicesLock.lock()
    defer { devicesLock.unlock() }
    return !devices.isEmpty
  }

  private var manager: IOHIDManager?
  private var devices: [String: DeviceRegistration] = [:]
  private let devicesLock = NSLock()
  private let pollQueue = DispatchQueue(
    label: "BridgeSense.RawDualSenseTouchpadReader.poll",
    qos: .userInitiated
  )
  private let outputQueue = DispatchQueue(
    label: "BridgeSense.RawDualSenseTouchpadReader.output",
    qos: .userInitiated
  )
  private var pollTimer: DispatchSourceTimer?

  deinit {
    stop()
  }

  func start() {
    guard manager == nil else {
      return
    }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      [kIOHIDVendorIDKey: Self.vendorID] as CFDictionary
    )

    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(
      manager,
      Self.deviceMatchedCallback,
      context
    )
    IOHIDManagerRegisterDeviceRemovalCallback(
      manager,
      Self.deviceRemovedCallback,
      context
    )
    IOHIDManagerScheduleWithRunLoop(
      manager,
      CFRunLoopGetMain(),
      CFRunLoopMode.commonModes.rawValue
    )
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      NSLog("BridgeSense: failed to open DualSense HID manager: 0x%08x", openResult)
      IOHIDManagerUnscheduleFromRunLoop(
        manager,
        CFRunLoopGetMain(),
        CFRunLoopMode.commonModes.rawValue
      )
      return
    }

    self.manager = manager

    if let existingDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
      for device in existingDevices {
        register(device: device)
      }
    }
  }

  func stop() {
    guard let manager else {
      return
    }

    stopPolling()

    devicesLock.lock()
    let registrations = Array(devices.values)
    devices.removeAll()
    devicesLock.unlock()

    for registration in registrations {
      IOHIDDeviceRegisterInputReportCallback(
        registration.device,
        registration.reportBuffer,
        registration.reportLength,
        nil,
        nil
      )
      IOHIDDeviceUnscheduleFromRunLoop(
        registration.device,
        CFRunLoopGetMain(),
        CFRunLoopMode.commonModes.rawValue
      )
      registration.reportBuffer.deallocate()
    }

    IOHIDManagerUnscheduleFromRunLoop(
      manager,
      CFRunLoopGetMain(),
      CFRunLoopMode.commonModes.rawValue
    )
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    self.manager = nil
  }

  func setAdaptiveTriggers(_ effect: DualSenseAdaptiveTriggerEffect) {
    guard let target = outputTarget() else {
      return
    }

    outputQueue.async {
      let report = Self.outputReport(
        effect: effect,
        isBluetooth: target.isBluetooth,
        sequence: target.sequence
      )
      let reportID = target.isBluetooth
        ? Self.outputReportIDBluetooth
        : Self.outputReportIDUSB
      let result = report.withUnsafeBufferPointer { buffer -> IOReturn in
        guard let baseAddress = buffer.baseAddress else {
          return kIOReturnBadArgument
        }
        return IOHIDDeviceSetReport(
          target.device,
          kIOHIDReportTypeOutput,
          CFIndex(reportID),
          baseAddress,
          report.count
        )
      }
      if result != kIOReturnSuccess {
        NSLog("BridgeSense: failed to send DualSense adaptive trigger report: 0x%08x", result)
      }
    }
  }

  private func register(device: IOHIDDevice) {
    guard isDualSense(device: device) else {
      return
    }

    let key = deviceKey(device)
    let reportLength = max(inputReportLength(for: device), 128)
    let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
    reportBuffer.initialize(repeating: 0, count: reportLength)

    let registration = DeviceRegistration(
      device: device,
      reportBuffer: reportBuffer,
      reportLength: reportLength
    )

    devicesLock.lock()
    if devices[key] == nil {
      devices[key] = registration
      devicesLock.unlock()
    } else {
      devicesLock.unlock()
      reportBuffer.deallocate()
      return
    }

    startPollingIfNeeded()

    IOHIDDeviceRegisterInputReportCallback(
      device,
      reportBuffer,
      reportLength,
      Self.inputReportCallback,
      Unmanaged.passUnretained(self).toOpaque()
    )
    IOHIDDeviceScheduleWithRunLoop(
      device,
      CFRunLoopGetMain(),
      CFRunLoopMode.commonModes.rawValue
    )
  }

  private func remove(device: IOHIDDevice) {
    let key = deviceKey(device)
    devicesLock.lock()
    let registration = devices.removeValue(forKey: key)
    let isEmpty = devices.isEmpty
    devicesLock.unlock()

    guard let registration else {
      return
    }

    IOHIDDeviceRegisterInputReportCallback(
      registration.device,
      registration.reportBuffer,
      registration.reportLength,
      nil,
      nil
    )
    IOHIDDeviceUnscheduleFromRunLoop(
      registration.device,
      CFRunLoopGetMain(),
      CFRunLoopMode.commonModes.rawValue
    )
    registration.reportBuffer.deallocate()
    if isEmpty {
      stopPolling()
    }
  }

  private func handle(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
    guard let sample = Self.touchpadSample(reportID: reportID, report: report, length: length) else {
      return
    }

    DispatchQueue.main.async { [weak self] in
      self?.onSample?(sample)
    }
  }

  private func pollFullReports() {
    let registrations = registeredDevices()
    guard !registrations.isEmpty else {
      DispatchQueue.main.async { [weak self] in
        self?.stopPolling()
      }
      return
    }

    for registration in registrations {
      if let sample = copyFullReportSample(
        device: registration.device,
        reportID: 0x31,
        length: registration.reportLength
      ) ?? copyFullReportSample(
        device: registration.device,
        reportID: 0x01,
        length: registration.reportLength
      ) {
        DispatchQueue.main.async { [weak self] in
          self?.onSample?(sample)
        }
      }
    }
  }

  private func registeredDevices() -> [DeviceRegistration] {
    devicesLock.lock()
    defer { devicesLock.unlock() }
    return Array(devices.values)
  }

  private func startPollingIfNeeded() {
    devicesLock.lock()
    let shouldStart = !devices.isEmpty && pollTimer == nil
    devicesLock.unlock()
    guard shouldStart else {
      return
    }

    let timer = DispatchSource.makeTimerSource(queue: pollQueue)
    timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
    timer.setEventHandler { [weak self] in
      self?.pollFullReports()
    }
    devicesLock.lock()
    if pollTimer == nil {
      pollTimer = timer
      devicesLock.unlock()
      timer.resume()
    } else {
      devicesLock.unlock()
      timer.cancel()
    }
  }

  private func stopPolling() {
    devicesLock.lock()
    let timer = pollTimer
    pollTimer = nil
    devicesLock.unlock()
    timer?.cancel()
  }

  private func outputTarget() -> OutputTarget? {
    devicesLock.lock()
    defer { devicesLock.unlock() }

    let registration = devices.values.first {
      outputReportLength(for: $0.device) >= Self.outputReportSizeUSB
    } ?? devices.values.first
    guard let registration else {
      return nil
    }

    let sequence = registration.outputSequence
    registration.outputSequence = (registration.outputSequence + 1) & 0x0f
    return OutputTarget(
      device: registration.device,
      isBluetooth: isBluetooth(device: registration.device),
      sequence: sequence
    )
  }

  private static func outputReport(
    effect: DualSenseAdaptiveTriggerEffect,
    isBluetooth: Bool,
    sequence: UInt8
  ) -> [UInt8] {
    let reportSize = isBluetooth ? outputReportSizeBluetooth : outputReportSizeUSB
    var report = [UInt8](repeating: 0, count: reportSize)
    let commonOffset: Int

    if isBluetooth {
      report[0] = UInt8(outputReportIDBluetooth)
      report[1] = (sequence & 0x0f) << 4
      report[2] = outputReportTagBluetooth
      commonOffset = 3
    } else {
      report[0] = UInt8(outputReportIDUSB)
      commonOffset = 1
    }

    report[commonOffset] = effect.sides.validFlag

    if effect.sides.contains(.right) {
      write(effect.bytes, to: &report, offset: commonOffset + 10)
    }
    if effect.sides.contains(.left) {
      write(effect.bytes, to: &report, offset: commonOffset + 21)
    }

    if isBluetooth {
      let crc = crc32(seed: outputReportCRCSeed, bytes: report, length: reportSize - 4)
      report[reportSize - 4] = UInt8(crc & 0xff)
      report[reportSize - 3] = UInt8((crc >> 8) & 0xff)
      report[reportSize - 2] = UInt8((crc >> 16) & 0xff)
      report[reportSize - 1] = UInt8((crc >> 24) & 0xff)
    }

    return report
  }

  private static func write(_ bytes: [UInt8], to report: inout [UInt8], offset: Int) {
    for (index, byte) in bytes.enumerated() where offset + index < report.count {
      report[offset + index] = byte
    }
  }

  private static func crc32(seed: UInt8, bytes: [UInt8], length: Int) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    crc = crc32(crc, byte: seed)
    for index in 0..<length {
      crc = crc32(crc, byte: bytes[index])
    }
    return ~crc
  }

  private static func crc32(_ crc: UInt32, byte: UInt8) -> UInt32 {
    var value = crc ^ UInt32(byte)
    for _ in 0..<8 {
      if value & 1 == 1 {
        value = (value >> 1) ^ 0xedb8_8320
      } else {
        value >>= 1
      }
    }
    return value
  }

  private func copyFullReportSample(
    device: IOHIDDevice,
    reportID: CFIndex,
    length: Int
  ) -> TouchpadSample? {
    var report = [UInt8](repeating: 0, count: length)
    var reportLength = report.count
    let result = report.withUnsafeMutableBufferPointer { buffer in
      IOHIDDeviceGetReport(
        device,
        kIOHIDReportTypeInput,
        reportID,
        buffer.baseAddress!,
        &reportLength
      )
    }
    guard result == kIOReturnSuccess else {
      return nil
    }
    return report.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return nil
      }
      return Self.touchpadSample(
        reportID: UInt32(reportID),
        report: baseAddress,
        length: reportLength
      )
    }
  }

  private static func touchpadSample(
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    length: Int
  ) -> TouchpadSample? {
    guard length > 0 else {
      return nil
    }

    let firstByte = report[0]
    let effectiveReportID = reportID == 0 ? UInt32(firstByte) : reportID
    let commonOffset: Int

    switch effectiveReportID {
    case 0x01:
      commonOffset = firstByte == 0x01 ? 1 : 0
    case 0x31:
      commonOffset = firstByte == 0x31 ? 2 : 1
    default:
      return nil
    }

    let buttons2Offset = commonOffset + 9
    let pointsOffset = commonOffset + 32
    guard length >= pointsOffset + 8, length > buttons2Offset else {
      return nil
    }

    let button = (report[buttons2Offset] & 0x02) != 0 ? 1.0 : 0.0

    for pointIndex in 0..<2 {
      let offset = pointsOffset + pointIndex * 4
      let contact = report[offset]
      let active = (contact & 0x80) == 0
      guard active else {
        continue
      }

      let x = Int(report[offset + 1]) | (Int(report[offset + 2] & 0x0f) << 8)
      let y = Int(report[offset + 2] >> 4) | (Int(report[offset + 3]) << 4)
      return TouchpadSample(
        point: CGPoint(
          x: normalizeX(x),
          y: normalizeY(y)
        ),
        button: button,
        active: true
      )
    }

    return .inactive(button: button)
  }

  private static func normalizeX(_ value: Int) -> Double {
    clamp((Double(value) / (touchpadWidth - 1)) * 2 - 1)
  }

  private static func normalizeY(_ value: Int) -> Double {
    clamp(1 - (Double(value) / (touchpadHeight - 1)) * 2)
  }

  private static func clamp(_ value: Double) -> Double {
    min(max(value, -1), 1)
  }

  private func inputReportLength(for device: IOHIDDevice) -> Int {
    let value = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString)
    return (value as? NSNumber)?.intValue ?? 128
  }

  private func outputReportLength(for device: IOHIDDevice) -> Int {
    let value = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)
    return (value as? NSNumber)?.intValue ?? 0
  }

  private func isBluetooth(device: IOHIDDevice) -> Bool {
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
    return transport?.localizedCaseInsensitiveContains("Bluetooth") == true
  }

  private func isDualSense(device: IOHIDDevice) -> Bool {
    if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber,
      Self.productIDs.contains(productID.intValue) {
      return true
    }

    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    return product?.localizedCaseInsensitiveContains("DualSense") == true
  }

  private func deviceKey(_ device: IOHIDDevice) -> String {
    String(describing: Unmanaged.passUnretained(device).toOpaque())
  }

  private struct OutputTarget {
    let device: IOHIDDevice
    let isBluetooth: Bool
    let sequence: UInt8
  }

  private final class DeviceRegistration {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let reportLength: Int
    var outputSequence: UInt8 = 0

    init(
      device: IOHIDDevice,
      reportBuffer: UnsafeMutablePointer<UInt8>,
      reportLength: Int
    ) {
      self.device = device
      self.reportBuffer = reportBuffer
      self.reportLength = reportLength
    }
  }

  private static let deviceMatchedCallback: IOHIDDeviceCallback = {
    context,
    _,
    _,
    device in
    guard let context else {
      return
    }
    let reader = Unmanaged<RawDualSenseTouchpadReader>
      .fromOpaque(context)
      .takeUnretainedValue()
    reader.register(device: device)
  }

  private static let deviceRemovedCallback: IOHIDDeviceCallback = {
    context,
    _,
    _,
    device in
    guard let context else {
      return
    }
    let reader = Unmanaged<RawDualSenseTouchpadReader>
      .fromOpaque(context)
      .takeUnretainedValue()
    reader.remove(device: device)
  }

  private static let inputReportCallback: IOHIDReportCallback = {
    context,
    result,
    _,
    reportType,
    reportID,
    report,
    reportLength in
    guard result == kIOReturnSuccess,
      reportType == kIOHIDReportTypeInput,
      let context else {
      return
    }

    let reader = Unmanaged<RawDualSenseTouchpadReader>
      .fromOpaque(context)
      .takeUnretainedValue()
    reader.handle(reportID: reportID, report: report, length: reportLength)
  }
}

private struct TouchpadSample {
  static let inactive = TouchpadSample(point: .zero, button: 0, active: false)

  let point: CGPoint
  let button: Double
  let active: Bool

  static func inactive(button: Double) -> TouchpadSample {
    TouchpadSample(point: .zero, button: button, active: false)
  }
}

private struct DualSenseTriggerSides: OptionSet {
  let rawValue: UInt8

  static let right = DualSenseTriggerSides(rawValue: 1 << 0)
  static let left = DualSenseTriggerSides(rawValue: 1 << 1)
  static let both: DualSenseTriggerSides = [.right, .left]

  var validFlag: UInt8 {
    var flag: UInt8 = 0
    if contains(.right) {
      flag |= 1 << 2
    }
    if contains(.left) {
      flag |= 1 << 3
    }
    return flag
  }
}

private struct DualSenseAdaptiveTriggerEffect {
  private static let modeOff: UInt8 = 0x05
  private static let modeFeedback: UInt8 = 0x21
  private static let modeWeapon: UInt8 = 0x25
  private static let modeVibration: UInt8 = 0x26

  let sides: DualSenseTriggerSides
  let bytes: [UInt8]

  static func effect(
    forHapticStyle style: String,
    sides requestedSides: DualSenseTriggerSides? = nil
  ) -> DualSenseAdaptiveTriggerEffect {
    switch style {
    case "engine":
      return .feedback(
        sides: requestedSides ?? .both,
        startPosition: 0.12,
        resistiveStrength: 0.35
      )
    case "gunshot":
      return .weapon(
        sides: requestedSides ?? .right,
        startPosition: 0.18,
        endPosition: 0.78,
        resistiveStrength: 0.95
      )
    default:
      return .vibration(
        sides: requestedSides ?? .both,
        startPosition: 0.12,
        amplitude: 0.45,
        frequency: 0.5
      )
    }
  }

  static func off(sides: DualSenseTriggerSides) -> DualSenseAdaptiveTriggerEffect {
    DualSenseAdaptiveTriggerEffect(
      sides: sides,
      bytes: [modeOff] + [UInt8](repeating: 0, count: 10)
    )
  }

  static func feedback(
    sides: DualSenseTriggerSides,
    startPosition: Float,
    resistiveStrength: Float
  ) -> DualSenseAdaptiveTriggerEffect {
    let position = normalizedPosition(startPosition)
    let strength = normalizedStrength(resistiveStrength)
    guard strength > 0 else {
      return .off(sides: sides)
    }
    return DualSenseAdaptiveTriggerEffect(
      sides: sides,
      bytes: [modeFeedback] + bitpackedZones(from: position, strength: strength, frequency: 0)
    )
  }

  static func weapon(
    sides: DualSenseTriggerSides,
    startPosition: Float,
    endPosition: Float,
    resistiveStrength: Float
  ) -> DualSenseAdaptiveTriggerEffect {
    let start = min(max(normalizedPosition(startPosition), 2), 7)
    let end = min(max(normalizedPosition(endPosition), start + 1), 8)
    let strength = normalizedStrength(resistiveStrength)
    guard strength > 0 else {
      return .off(sides: sides)
    }

    let zones = UInt16(1 << start) | UInt16(1 << end)
    let params: [UInt8] = [
      UInt8(zones & 0xff),
      UInt8((zones >> 8) & 0xff),
      UInt8(strength - 1),
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]
    return DualSenseAdaptiveTriggerEffect(sides: sides, bytes: [modeWeapon] + params)
  }

  static func vibration(
    sides: DualSenseTriggerSides,
    startPosition: Float,
    amplitude: Float,
    frequency: Float
  ) -> DualSenseAdaptiveTriggerEffect {
    let position = normalizedPosition(startPosition)
    let strength = normalizedStrength(amplitude)
    let rawFrequency = normalizedFrequency(frequency)
    guard strength > 0, rawFrequency > 0 else {
      return .off(sides: sides)
    }
    return DualSenseAdaptiveTriggerEffect(
      sides: sides,
      bytes: [modeVibration]
        + bitpackedZones(from: position, strength: strength, frequency: rawFrequency)
    )
  }

  private static func bitpackedZones(
    from position: Int,
    strength: Int,
    frequency: Int
  ) -> [UInt8] {
    var activeZones: UInt16 = 0
    var strengthZones: UInt32 = 0
    let strengthValue = UInt32((strength - 1) & 0x07)

    for index in position..<10 {
      activeZones |= UInt16(1 << index)
      strengthZones |= strengthValue << (3 * index)
    }

    return [
      UInt8(activeZones & 0xff),
      UInt8((activeZones >> 8) & 0xff),
      UInt8(strengthZones & 0xff),
      UInt8((strengthZones >> 8) & 0xff),
      UInt8((strengthZones >> 16) & 0xff),
      UInt8((strengthZones >> 24) & 0xff),
      0,
      0,
      UInt8(frequency),
      0,
    ]
  }

  private static func normalizedPosition(_ value: Float) -> Int {
    min(max(Int((value * 9).rounded()), 0), 9)
  }

  private static func normalizedStrength(_ value: Float) -> Int {
    min(max(Int((value * 8).rounded()), 0), 8)
  }

  private static func normalizedFrequency(_ value: Float) -> Int {
    min(max(Int((value * 255).rounded()), 0), 255)
  }
}

private enum BridgeSenseError: LocalizedError {
  case hapticsUnavailable

  var errorDescription: String? {
    switch self {
    case .hapticsUnavailable:
      return "No controller haptics engine is available."
    }
  }
}

private enum BridgeAction: String {
  case none
  case cursor
  case scroll
  case key
  case mouseClick
  case haptic
}

private enum MouseButton: String {
  case left
  case right

  var cgButton: CGMouseButton {
    switch self {
    case .left:
      return .left
    case .right:
      return .right
    }
  }

  var downEvent: CGEventType {
    switch self {
    case .left:
      return .leftMouseDown
    case .right:
      return .rightMouseDown
    }
  }

  var upEvent: CGEventType {
    switch self {
    case .left:
      return .leftMouseUp
    case .right:
      return .rightMouseUp
    }
  }

  var actionDescription: String {
    switch self {
    case .left:
      return "left click"
    case .right:
      return "right click"
    }
  }
}

private struct BridgeSettings {
  static let defaults = BridgeSettings(pointerSpeed: 22, scrollSpeed: 14, deadZone: 0.12)

  let pointerSpeed: Double
  let scrollSpeed: Double
  let deadZone: Double

  init(pointerSpeed: Double, scrollSpeed: Double, deadZone: Double) {
    self.pointerSpeed = min(max(pointerSpeed, 4), 56)
    self.scrollSpeed = min(max(scrollSpeed, 2), 36)
    self.deadZone = min(max(deadZone, 0.03), 0.35)
  }

  init?(dictionary: [String: Any]?) {
    guard let dictionary else {
      return nil
    }
    self.init(
      pointerSpeed: BridgeSettings.doubleValue(dictionary["pointerSpeed"], fallback: 22),
      scrollSpeed: BridgeSettings.doubleValue(dictionary["scrollSpeed"], fallback: 14),
      deadZone: BridgeSettings.doubleValue(dictionary["deadZone"], fallback: 0.12)
    )
  }

  var dictionary: [String: Any] {
    [
      "pointerSpeed": pointerSpeed,
      "scrollSpeed": scrollSpeed,
      "deadZone": deadZone,
    ]
  }

  private static func doubleValue(_ value: Any?, fallback: Double) -> Double {
    if let value = value as? Double {
      return value
    }
    if let value = value as? NSNumber {
      return value.doubleValue
    }
    return fallback
  }
}

private struct BridgeMapping {
  static let defaults: [BridgeMapping] = [
    BridgeMapping(id: "leftStick", controlLabel: "L stick", action: .cursor, label: "Cursor"),
    BridgeMapping(id: "rightStick", controlLabel: "R stick", action: .scroll, label: "Scroll"),
    BridgeMapping(id: "touchpadMotion", controlLabel: "Touchpad move", action: .cursor, label: "Mouse move"),
    BridgeMapping(id: "l2", controlLabel: "L2"),
    BridgeMapping(id: "r2", controlLabel: "R2"),
    BridgeMapping(id: "l1", controlLabel: "L1"),
    BridgeMapping(id: "r1", controlLabel: "R1"),
    BridgeMapping(id: "cross", controlLabel: "Cross / A"),
    BridgeMapping(id: "circle", controlLabel: "Circle / B"),
    BridgeMapping(id: "square", controlLabel: "Square / X"),
    BridgeMapping(id: "triangle", controlLabel: "Triangle / Y"),
    BridgeMapping(id: "dpadUp", controlLabel: "D-pad up"),
    BridgeMapping(id: "dpadDown", controlLabel: "D-pad down"),
    BridgeMapping(id: "dpadLeft", controlLabel: "D-pad left"),
    BridgeMapping(id: "dpadRight", controlLabel: "D-pad right"),
    BridgeMapping(id: "leftStickButton", controlLabel: "L3"),
    BridgeMapping(id: "rightStickButton", controlLabel: "R3"),
    BridgeMapping(id: "menu", controlLabel: "Menu"),
    BridgeMapping(id: "options", controlLabel: "Options"),
    BridgeMapping(id: "home", controlLabel: "PS / Home"),
    BridgeMapping(id: "touchpad", controlLabel: "Touchpad click"),
  ]

  let id: String
  let controlLabel: String
  let action: BridgeAction
  let label: String
  let keyCode: UInt16?
  let keyLabel: String
  let mouseButton: MouseButton
  let modifiers: [String]
  let vibrate: Bool
  let hapticStyle: String

  init(
    id: String,
    controlLabel: String,
    action: BridgeAction = .none,
    label: String = "",
    keyCode: UInt16? = nil,
    keyLabel: String = "",
    mouseButton: MouseButton = .left,
    modifiers: [String] = [],
    vibrate: Bool = false,
    hapticStyle: String = "pulse"
  ) {
    self.id = id
    self.controlLabel = controlLabel
    self.action = action
    self.label = label
    self.keyCode = keyCode
    self.keyLabel = keyLabel
    self.mouseButton = mouseButton
    self.modifiers = modifiers
    self.vibrate = vibrate
    self.hapticStyle = hapticStyle
  }

  init?(dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? String,
      let fallback = BridgeMapping.defaults.first(where: { $0.id == id }) else {
      return nil
    }

    let rawAction = dictionary["action"] as? String ?? fallback.action.rawValue
    var action = BridgeAction(rawValue: rawAction) ?? fallback.action
    let vibrate = (dictionary["vibrate"] as? Bool ?? fallback.vibrate) || action == .haptic
    if action == .haptic {
      action = .none
    }
    let keyCode: UInt16?
    if let number = dictionary["keyCode"] as? NSNumber {
      keyCode = number.uint16Value
    } else if let int = dictionary["keyCode"] as? Int {
      keyCode = UInt16(int)
    } else {
      keyCode = fallback.keyCode
    }

    self.init(
      id: id,
      controlLabel: dictionary["controlLabel"] as? String ?? fallback.controlLabel,
      action: action,
      label: dictionary["label"] as? String ?? fallback.label,
      keyCode: keyCode,
      keyLabel: dictionary["keyLabel"] as? String ?? fallback.keyLabel,
      mouseButton: MouseButton(rawValue: dictionary["mouseButton"] as? String ?? "") ?? fallback.mouseButton,
      modifiers: dictionary["modifiers"] as? [String] ?? fallback.modifiers,
      vibrate: vibrate,
      hapticStyle: dictionary["hapticStyle"] as? String ?? fallback.hapticStyle
    )
  }

  func dictionary(includeNil: Bool) -> [String: Any] {
    var dictionary: [String: Any] = [
      "id": id,
      "controlLabel": controlLabel,
      "action": action.rawValue,
      "label": label,
      "keyLabel": keyLabel,
      "mouseButton": mouseButton.rawValue,
      "modifiers": modifiers,
      "vibrate": vibrate,
      "hapticStyle": hapticStyle,
    ]
    if let keyCode {
      dictionary["keyCode"] = Int(keyCode)
    } else if includeNil {
      dictionary["keyCode"] = NSNull()
    }
    return dictionary
  }
}
