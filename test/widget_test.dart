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
}
