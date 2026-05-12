import 'package:bridge_sense/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows default bridge bindings without manual vibration panel', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BridgeSenseApp());
    await tester.pump();

    expect(find.text('BridgeSense'), findsOneWidget);
    expect(find.text('L stick'), findsWidgets);
    expect(find.text('R stick'), findsWidgets);
    expect(find.text('Touchpad'), findsWidgets);
    expect(find.text('L2'), findsWidgets);
    expect(find.text('R2'), findsWidgets);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Off'), findsWidgets);
    expect(find.text('Vibrate'), findsWidgets);
    expect(find.text('Drive'), findsNothing);
    expect(find.text('Shoot'), findsNothing);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Purpose'), findsNothing);
  });

  testWidgets('key binding row aligns key and moves haptics below modifiers', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var mapping = const BridgeMapping(
      id: 'square',
      controlLabel: 'Square / X',
      action: 'key',
      label: 'Confirm',
      keyCode: 36,
      keyLabel: 'Return',
      modifiers: [],
      vibrate: true,
      hapticStyle: 'gunshot',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return MappingRow(
                    mapping: mapping,
                    onChanged: (value) => setState(() => mapping = value),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Square / X'), findsOneWidget);
    expect(find.text('Modifiers'), findsOneWidget);
    expect(find.text('Haptics'), findsOneWidget);
    expect(find.text('Purpose'), findsNothing);
    expect(find.text('Return'), findsOneWidget);
    expect(find.text('Shoot'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Shoot')).dy,
      greaterThan(tester.getTopLeft(find.text('Modifiers')).dy),
    );
  });

  testWidgets('mouse click binding exposes left and right buttons', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var mapping = const BridgeMapping(
      id: 'cross',
      controlLabel: 'Cross / A',
      action: 'mouseClick',
      label: '',
      keyCode: null,
      keyLabel: '',
      mouseButton: 'right',
      modifiers: [],
      vibrate: false,
      hapticStyle: 'pulse',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return MappingRow(
                    mapping: mapping,
                    onChanged: (value) => setState(() => mapping = value),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mouse click'), findsOneWidget);
    expect(find.text('Right click'), findsOneWidget);
    expect(find.text('Key'), findsNothing);

    await tester.tap(find.text('Right click'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left click').last);
    await tester.pumpAndSettle();

    expect(mapping.mouseButton, 'left');
    expect(find.text('Left click'), findsOneWidget);
  });

  testWidgets('runtime panel hides last action text', (
    WidgetTester tester,
  ) async {
    final snapshot = ControllerSnapshot.empty().copyWith(
      lastAction: 'Square / X: Confirm -> Return; vibration gunshot',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatusPanel(snapshot: snapshot)),
      ),
    );

    expect(find.text('Runtime'), findsOneWidget);
    expect(find.textContaining('Square / X:'), findsNothing);
  });

  test('snapshot parses active profile and connected controllers', () {
    final snapshot = ControllerSnapshot.fromDynamic({
      'connected': true,
      'controllerName': 'DualSense Wireless Controller',
      'productCategory': 'DualSense',
      'controllerType': 'dualSense',
      'activeProfileId': 'switchPro',
      'activeProfileName': 'Switch Pro',
      'connectedControllers': [
        {
          'id': 'dual',
          'name': 'DualSense Wireless Controller',
          'productCategory': 'DualSense',
          'controllerType': 'dualSense',
          'profileName': 'DualSense',
          'active': false,
        },
        {
          'id': 'switch',
          'name': 'Pro Controller',
          'productCategory': 'HID',
          'controllerType': 'switchPro',
          'profileName': 'Switch Pro',
          'active': true,
        },
      ],
      'supportedControlIds': switchSupportedControlIds.toList(),
    });

    expect(snapshot.activeProfileId, 'switchPro');
    expect(snapshot.activeProfileName, 'Switch Pro');
    expect(snapshot.controllerType, 'dualSense');
    expect(snapshot.connectedControllers, hasLength(2));
    expect(snapshot.connectedControllers.last.active, isTrue);
    expect(snapshot.supportsControl('touchpadMotion'), isFalse);
  });

  testWidgets('profile selector exposes tabs for each saved profile', (
    WidgetTester tester,
  ) async {
    String? selectedProfile;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: ProfileSelector(
              snapshot: switchProfileSnapshot(),
              onProfileChanged: (profileId) => selectedProfile = profileId,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('DualSense'), findsOneWidget);
    expect(find.text('Switch Pro'), findsOneWidget);
    expect(find.text('Xbox'), findsOneWidget);
    expect(find.text('Generic'), findsOneWidget);
    expect(find.byIcon(Icons.sports_esports), findsNWidgets(3));
    expect(find.byIcon(Icons.gamepad), findsOneWidget);

    await tester.tap(find.text('Xbox'));
    expect(selectedProfile, 'xbox');
  });

  testWidgets('profile selector uses picker in compact layouts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ProfileSelector(
              snapshot: switchProfileSnapshot(),
              onProfileChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Editing profile'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('runtime panel shows editing profile and controller count', (
    WidgetTester tester,
  ) async {
    final snapshot = switchProfileSnapshot();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatusPanel(snapshot: snapshot)),
      ),
    );

    expect(find.text('Editing profile'), findsOneWidget);
    expect(find.text('Switch Pro'), findsWidgets);
    expect(find.text('Controllers'), findsOneWidget);
    expect(find.text('2 connected'), findsOneWidget);
    expect(find.text('Controller type'), findsOneWidget);
  });

  testWidgets('switch profile hides touchpad motion controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: AxisBindingsPanel(
              snapshot: switchProfileSnapshot(),
              onMappingChanged: (_) {},
              onSettingsChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('L stick'), findsOneWidget);
    expect(find.text('R stick'), findsOneWidget);
    expect(find.text('Touchpad'), findsNothing);
  });

  testWidgets('switch profile uses Nintendo button labels', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: ButtonBindingsPanel(
              snapshot: switchProfileSnapshot(),
              onMappingChanged: (_) {},
              onReset: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Y'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Touchpad click'), findsNothing);
  });

  testWidgets('xbox profile uses Xbox button labels', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: ButtonBindingsPanel(
              snapshot: xboxProfileSnapshot(),
              onMappingChanged: (_) {},
              onReset: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('LT'), findsOneWidget);
    expect(find.text('RT'), findsOneWidget);
    expect(find.text('LB'), findsOneWidget);
    expect(find.text('RB'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Y'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Xbox'), findsOneWidget);
    expect(find.text('Touchpad click'), findsNothing);
  });
}

const standardControllerSupportedControlIds = {
  'leftStick',
  'rightStick',
  'l2',
  'r2',
  'l1',
  'r1',
  'cross',
  'circle',
  'square',
  'triangle',
  'dpadUp',
  'dpadDown',
  'dpadLeft',
  'dpadRight',
  'leftStickButton',
  'rightStickButton',
  'menu',
  'options',
  'home',
};

const switchSupportedControlIds = standardControllerSupportedControlIds;
const xboxSupportedControlIds = standardControllerSupportedControlIds;

ControllerSnapshot switchProfileSnapshot() {
  return ControllerSnapshot.empty().copyWith(
    connected: true,
    controllerName: 'Pro Controller',
    productCategory: 'HID',
    controllerType: 'switchPro',
    activeProfileId: 'switchPro',
    activeProfileName: 'Switch Pro',
    connectedControllers: const [
      ConnectedController(
        id: 'dual',
        name: 'DualSense Wireless Controller',
        productCategory: 'DualSense',
        controllerType: 'dualSense',
        profileName: 'DualSense',
        active: false,
      ),
      ConnectedController(
        id: 'switch',
        name: 'Pro Controller',
        productCategory: 'HID',
        controllerType: 'switchPro',
        profileName: 'Switch Pro',
        active: true,
      ),
    ],
    supportedControlIds: switchSupportedControlIds,
    mappings: [
      for (final mapping in defaultMappings)
        if (switchSupportedControlIds.contains(mapping.id))
          switch (mapping.id) {
            'cross' => const BridgeMapping(
              id: 'cross',
              controlLabel: 'B',
              action: 'none',
              label: '',
              keyCode: null,
              keyLabel: '',
              modifiers: [],
              vibrate: false,
              hapticStyle: 'pulse',
            ),
            'circle' => const BridgeMapping(
              id: 'circle',
              controlLabel: 'A',
              action: 'none',
              label: '',
              keyCode: null,
              keyLabel: '',
              modifiers: [],
              vibrate: false,
              hapticStyle: 'pulse',
            ),
            'square' => const BridgeMapping(
              id: 'square',
              controlLabel: 'Y',
              action: 'none',
              label: '',
              keyCode: null,
              keyLabel: '',
              modifiers: [],
              vibrate: false,
              hapticStyle: 'pulse',
            ),
            'triangle' => const BridgeMapping(
              id: 'triangle',
              controlLabel: 'X',
              action: 'none',
              label: '',
              keyCode: null,
              keyLabel: '',
              modifiers: [],
              vibrate: false,
              hapticStyle: 'pulse',
            ),
            _ => mapping,
          },
    ],
  );
}

ControllerSnapshot xboxProfileSnapshot() {
  return ControllerSnapshot.empty().copyWith(
    connected: true,
    controllerName: 'Xbox Wireless Controller',
    productCategory: 'HID',
    controllerType: 'xbox',
    activeProfileId: 'xbox',
    activeProfileName: 'Xbox',
    connectedControllers: const [
      ConnectedController(
        id: 'xbox',
        name: 'Xbox Wireless Controller',
        productCategory: 'HID',
        controllerType: 'xbox',
        profileName: 'Xbox',
        active: true,
      ),
    ],
    supportedControlIds: xboxSupportedControlIds,
    mappings: [
      for (final mapping in defaultMappings)
        if (xboxSupportedControlIds.contains(mapping.id))
          switch (mapping.id) {
            'l2' => xboxMapping(mapping, 'LT'),
            'r2' => xboxMapping(mapping, 'RT'),
            'l1' => xboxMapping(mapping, 'LB'),
            'r1' => xboxMapping(mapping, 'RB'),
            'cross' => xboxMapping(mapping, 'A'),
            'circle' => xboxMapping(mapping, 'B'),
            'square' => xboxMapping(mapping, 'X'),
            'triangle' => xboxMapping(mapping, 'Y'),
            'leftStickButton' => xboxMapping(mapping, 'LS'),
            'rightStickButton' => xboxMapping(mapping, 'RS'),
            'options' => xboxMapping(mapping, 'View'),
            'menu' => xboxMapping(mapping, 'Menu'),
            'home' => xboxMapping(mapping, 'Xbox'),
            _ => mapping,
          },
    ],
  );
}

BridgeMapping xboxMapping(BridgeMapping mapping, String controlLabel) {
  return BridgeMapping(
    id: mapping.id,
    controlLabel: controlLabel,
    action: mapping.action,
    label: mapping.label,
    keyCode: mapping.keyCode,
    keyLabel: mapping.keyLabel,
    modifiers: mapping.modifiers,
    vibrate: mapping.vibrate,
    hapticStyle: mapping.hapticStyle,
  );
}
