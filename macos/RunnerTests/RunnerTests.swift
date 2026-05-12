import Cocoa
@testable import BridgeSense
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testControllerTypeResolverRecognizesDualSenseAndSwitchPro() {
    XCTAssertEqual(
      BridgeControllerProfileType.resolve(
        vendorName: "DualSense Wireless Controller",
        productCategory: "DualSense"
      ),
      .dualSense
    )
    XCTAssertEqual(
      BridgeControllerProfileType.resolve(
        vendorName: "Pro Controller",
        productCategory: "HID"
      ),
      .switchPro
    )
    XCTAssertEqual(
      BridgeControllerProfileType.resolve(
        vendorName: "Xbox Wireless Controller",
        productCategory: "HID"
      ),
      .generic
    )
  }

  func testSwitchProfileDefaultsUseNintendoLabelsAndHideTouchpad() {
    let profile = BridgeProfile(type: .switchPro)
    let ids = Set(profile.mappings.map(\.id))

    XCTAssertFalse(ids.contains("touchpadMotion"))
    XCTAssertFalse(ids.contains("touchpad"))
    XCTAssertEqual(profile.mappings.first { $0.id == "cross" }?.controlLabel, "B")
    XCTAssertEqual(profile.mappings.first { $0.id == "circle" }?.controlLabel, "A")
    XCTAssertEqual(profile.mappings.first { $0.id == "square" }?.controlLabel, "Y")
    XCTAssertEqual(profile.mappings.first { $0.id == "triangle" }?.controlLabel, "X")
    XCTAssertEqual(profile.mappings.first { $0.id == "options" }?.controlLabel, "Minus")
    XCTAssertEqual(profile.mappings.first { $0.id == "menu" }?.controlLabel, "Plus")
  }

  func testProfileStoreMigratesLegacyGlobalsIntoDualSenseOnly() {
    var store = BridgeProfileStore(
      legacyMappings: [
        [
          "id": "cross",
          "controlLabel": "Cross / A",
          "action": "key",
          "label": "Accept",
          "keyCode": 36,
          "keyLabel": "Return",
          "modifiers": [],
          "vibrate": true,
          "hapticStyle": "pulse",
        ],
      ],
      legacySettings: [
        "pointerSpeed": 40,
        "scrollSpeed": 20,
        "deadZone": 0.2,
      ]
    )

    let dualSense = store.profile(for: .dualSense)
    let switchPro = store.profile(for: .switchPro)

    XCTAssertEqual(dualSense.settings.pointerSpeed, 40)
    XCTAssertEqual(dualSense.mappings.first { $0.id == "cross" }?.action, BridgeAction.key)
    XCTAssertEqual(dualSense.mappings.first { $0.id == "cross" }?.keyCode, 36)
    XCTAssertEqual(switchPro.settings.pointerSpeed, BridgeSettings.defaults.pointerSpeed)
    XCTAssertEqual(switchPro.mappings.first { $0.id == "cross" }?.action, BridgeAction.none)
  }

  func testProfileStoreRoundTripsProfilesIndependently() {
    var store = BridgeProfileStore()
    var switchProfile = store.profile(for: .switchPro)
    switchProfile.settings = BridgeSettings(pointerSpeed: 33, scrollSpeed: 11, deadZone: 0.18)
    switchProfile.mappings = switchProfile.mappings.map { mapping in
      guard mapping.id == "circle" else {
        return mapping
      }
      return BridgeMapping(
        id: mapping.id,
        controlLabel: mapping.controlLabel,
        action: .mouseClick,
        label: mapping.label,
        keyCode: mapping.keyCode,
        keyLabel: mapping.keyLabel,
        mouseButton: .right,
        modifiers: mapping.modifiers,
        vibrate: mapping.vibrate,
        hapticStyle: mapping.hapticStyle
      )
    }
    store.update(switchProfile)

    var reloaded = BridgeProfileStore(savedProfiles: store.dictionary)
    let loadedSwitch = reloaded.profile(for: .switchPro)
    let loadedDualSense = reloaded.profile(for: .dualSense)

    XCTAssertEqual(loadedSwitch.settings.pointerSpeed, 33)
    XCTAssertEqual(
      loadedSwitch.mappings.first { $0.id == "circle" }?.action,
      BridgeAction.mouseClick
    )
    XCTAssertEqual(
      loadedSwitch.mappings.first { $0.id == "circle" }?.mouseButton,
      MouseButton.right
    )
    XCTAssertEqual(loadedDualSense.settings.pointerSpeed, BridgeSettings.defaults.pointerSpeed)
  }

  func testActiveControllerSelectorPrefersCurrentThenPreviousThenFirst() {
    XCTAssertEqual(
      ActiveControllerSelector.select(
        candidateIDs: ["dual", "switch"],
        currentID: "switch",
        previousActiveID: "dual"
      ),
      "switch"
    )
    XCTAssertEqual(
      ActiveControllerSelector.select(
        candidateIDs: ["dual", "switch"],
        currentID: nil,
        previousActiveID: "dual"
      ),
      "dual"
    )
    XCTAssertEqual(
      ActiveControllerSelector.select(
        candidateIDs: ["dual", "switch"],
        currentID: nil,
        previousActiveID: nil
      ),
      "dual"
    )
  }

  func testActiveControllerSelectorRoutesAllConnectedControllersForOutput() {
    XCTAssertEqual(
      ActiveControllerSelector.outputControllerIDs(candidateIDs: ["dual", "switch"]),
      ["dual", "switch"]
    )
  }

}
