import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const BridgeSenseApp());
}

class BridgeSenseApp extends StatelessWidget {
  const BridgeSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BridgeSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF227C6F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFD9DDD5)),
          ),
        ),
      ),
      home: const BridgeSenseHome(),
    );
  }
}

class BridgeSenseHome extends StatefulWidget {
  const BridgeSenseHome({super.key});

  @override
  State<BridgeSenseHome> createState() => _BridgeSenseHomeState();
}

class _BridgeSenseHomeState extends State<BridgeSenseHome> {
  final NativeBridge _bridge = NativeBridge();
  ControllerSnapshot _snapshot = ControllerSnapshot.empty();
  StreamSubscription<ControllerSnapshot>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
    _subscription = _bridge.watch().listen(
      (snapshot) => setState(() => _snapshot = snapshot),
      onError: (_) {},
    );
  }

  Future<void> _loadSnapshot() async {
    final snapshot = await _bridge.snapshot();
    if (mounted) {
      setState(() => _snapshot = snapshot);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _setBridgeEnabled(bool enabled) async {
    setState(() => _snapshot = _snapshot.copyWith(bridgeEnabled: enabled));
    await _bridge.setBridgeEnabled(enabled);
    await _loadSnapshot();
  }

  Future<void> _requestAccessibility() async {
    await _bridge.requestAccessibility();
    await _loadSnapshot();
  }

  Future<void> _selectProfile(String profileId) async {
    if (profileId == _snapshot.activeProfileId) {
      return;
    }
    final snapshot = await _bridge.setActiveProfile(profileId);
    if (mounted) {
      setState(() => _snapshot = snapshot);
    }
  }

  Future<void> _updateMapping(BridgeMapping mapping) async {
    final mappings = _snapshot.mappings
        .map((item) => item.id == mapping.id ? mapping : item)
        .toList(growable: false);
    setState(() => _snapshot = _snapshot.copyWith(mappings: mappings));
    await _bridge.setMappings(mappings);
  }

  Future<void> _resetMappings() async {
    final snapshot = await _bridge.resetMappings();
    if (mounted) {
      setState(() => _snapshot = snapshot);
    }
  }

  Future<void> _updateSettings(BridgeSettings settings) async {
    setState(() => _snapshot = _snapshot.copyWith(settings: settings));
    await _bridge.setSettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HeaderBar(
              snapshot: _snapshot,
              onBridgeChanged: _setBridgeEnabled,
              onRequestAccessibility: _requestAccessibility,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final leftColumn = [StatusPanel(snapshot: _snapshot)];
                  final rightColumn = [
                    ProfileSelector(
                      snapshot: _snapshot,
                      onProfileChanged: _selectProfile,
                    ),
                    const SizedBox(height: 14),
                    AxisBindingsPanel(
                      snapshot: _snapshot,
                      onMappingChanged: _updateMapping,
                      onSettingsChanged: _updateSettings,
                    ),
                    const SizedBox(height: 14),
                    ButtonBindingsPanel(
                      snapshot: _snapshot,
                      onMappingChanged: _updateMapping,
                      onReset: _resetMappings,
                    ),
                  ];

                  if (constraints.maxWidth < 980) {
                    return ListView(
                      children: [
                        ...leftColumn,
                        const SizedBox(height: 14),
                        ...rightColumn,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 360,
                        child: ListView(children: leftColumn),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: ListView(children: rightColumn)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.snapshot,
    required this.onBridgeChanged,
    required this.onRequestAccessibility,
  });

  final ControllerSnapshot snapshot;
  final ValueChanged<bool> onBridgeChanged;
  final VoidCallback onRequestAccessibility;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.gamepad, color: scheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BridgeSense',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                snapshot.connected
                    ? '${snapshot.connectedControllerSummary} - editing ${snapshot.activeProfileName} profile'
                    : 'Editing ${snapshot.activeProfileName} profile',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Accessibility permission',
          child: OutlinedButton.icon(
            onPressed: snapshot.accessibilityTrusted
                ? null
                : onRequestAccessibility,
            icon: Icon(
              snapshot.accessibilityTrusted
                  ? Icons.verified_user
                  : Icons.admin_panel_settings,
            ),
            label: Text(snapshot.accessibilityTrusted ? 'Trusted' : 'Request'),
          ),
        ),
        const SizedBox(width: 10),
        Switch(value: snapshot.bridgeEnabled, onChanged: onBridgeChanged),
      ],
    );
  }
}

class ProfileSelector extends StatelessWidget {
  const ProfileSelector({
    super.key,
    required this.snapshot,
    required this.onProfileChanged,
  });

  final ControllerSnapshot snapshot;
  final ValueChanged<String> onProfileChanged;

  @override
  Widget build(BuildContext context) {
    final selectedProfileId =
        controllerProfileOptions.any(
          (profile) => profile.id == snapshot.activeProfileId,
        )
        ? snapshot.activeProfileId
        : controllerProfileOptions.first.id;

    return SectionCard(
      title: 'Profiles',
      icon: Icons.tune,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return DropdownButtonFormField<String>(
              key: ValueKey('profile-picker-$selectedProfileId'),
              initialValue: selectedProfileId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Editing profile',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final profile in controllerProfileOptions)
                  DropdownMenuItem(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onProfileChanged(value);
                }
              },
            );
          }

          return SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              selected: {selectedProfileId},
              showSelectedIcon: false,
              segments: [
                for (final profile in controllerProfileOptions)
                  ButtonSegment<String>(
                    value: profile.id,
                    icon: Icon(profile.icon, size: 18),
                    label: Text(profile.name),
                  ),
              ],
              onSelectionChanged: (selection) =>
                  onProfileChanged(selection.first),
            ),
          );
        },
      ),
    );
  }
}

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, required this.snapshot});

  final ControllerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Runtime',
      icon: Icons.sensors,
      child: Column(
        children: [
          StatusLine(
            label: 'Controller',
            value: snapshot.connected ? 'Connected' : 'Disconnected',
            active: snapshot.connected,
          ),
          StatusLine(
            label: 'Editing profile',
            value: snapshot.activeProfileName,
            active: snapshot.connected,
          ),
          StatusLine(
            label: 'Controllers',
            value: snapshot.connectedControllerSummary,
            active: snapshot.connectedControllers.isNotEmpty,
          ),
          StatusLine(
            label: 'Controller type',
            value: controllerTypeLabel(snapshot.controllerType),
            active: snapshot.connected,
          ),
          StatusLine(
            label: 'Output',
            value: snapshot.accessibilityTrusted ? 'Ready' : 'Blocked',
            active: snapshot.accessibilityTrusted,
          ),
          StatusLine(
            label: 'Vibration',
            value: snapshot.hapticsAvailable ? 'Available' : 'Unavailable',
            active: snapshot.hapticsAvailable,
          ),
          StatusLine(
            label: 'Adaptive triggers',
            value: snapshot.adaptiveTriggersAvailable ? 'Available' : 'Off',
            active: snapshot.adaptiveTriggersAvailable,
          ),
        ],
      ),
    );
  }
}

class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.remove_circle_outline,
            size: 18,
            color: active ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class AxisBindingsPanel extends StatelessWidget {
  const AxisBindingsPanel({
    super.key,
    required this.snapshot,
    required this.onMappingChanged,
    required this.onSettingsChanged,
  });

  final ControllerSnapshot snapshot;
  final ValueChanged<BridgeMapping> onMappingChanged;
  final ValueChanged<BridgeSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final motionRows = [
      ('leftStick', 'L stick'),
      ('rightStick', 'R stick'),
      ('touchpadMotion', 'Touchpad'),
    ].where((row) => snapshot.supportsControl(row.$1)).toList(growable: false);

    return SectionCard(
      title: 'Motion bindings',
      icon: Icons.control_camera,
      child: Column(
        children: [
          for (final row in motionRows) ...[
            StickBindingRow(
              title: row.$2,
              mapping: snapshot.mappingFor(row.$1),
              onChanged: onMappingChanged,
            ),
            if (row != motionRows.last) const SizedBox(height: 10),
          ],
          const Divider(height: 28),
          SettingsSlider(
            label: 'Cursor speed',
            value: snapshot.settings.pointerSpeed,
            min: 4,
            max: 56,
            onChanged: (value) => onSettingsChanged(
              snapshot.settings.copyWith(pointerSpeed: value),
            ),
          ),
          SettingsSlider(
            label: 'Scroll speed',
            value: snapshot.settings.scrollSpeed,
            min: 2,
            max: 36,
            onChanged: (value) => onSettingsChanged(
              snapshot.settings.copyWith(scrollSpeed: value),
            ),
          ),
          SettingsSlider(
            label: 'Dead zone',
            value: snapshot.settings.deadZone,
            min: 0.03,
            max: 0.35,
            onChanged: (value) =>
                onSettingsChanged(snapshot.settings.copyWith(deadZone: value)),
          ),
        ],
      ),
    );
  }
}

class StickBindingRow extends StatelessWidget {
  const StickBindingRow({
    super.key,
    required this.title,
    required this.mapping,
    required this.onChanged,
  });

  final String title;
  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('${mapping.id}-${mapping.action}'),
            initialValue: mapping.action,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'cursor', child: Text('Cursor')),
              DropdownMenuItem(value: 'scroll', child: Text('Scroll')),
              DropdownMenuItem(value: 'none', child: Text('Off')),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(mapping.copyWith(action: value));
              }
            },
          ),
        ),
      ],
    );
  }
}

class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 112, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(value.toStringAsFixed(2), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class ButtonBindingsPanel extends StatelessWidget {
  const ButtonBindingsPanel({
    super.key,
    required this.snapshot,
    required this.onMappingChanged,
    required this.onReset,
  });

  final ControllerSnapshot snapshot;
  final ValueChanged<BridgeMapping> onMappingChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final buttonMappings = snapshot.mappings
        .where(
          (mapping) =>
              !mapping.isMotionControl && snapshot.supportsControl(mapping.id),
        )
        .toList(growable: false);
    return SectionCard(
      title: 'Button bindings',
      icon: Icons.keyboard_command_key,
      trailing: IconButton(
        tooltip: 'Reset editing profile bindings',
        onPressed: onReset,
        icon: const Icon(Icons.restore),
      ),
      child: Column(
        children: [
          for (final mapping in buttonMappings) ...[
            MappingRow(mapping: mapping, onChanged: onMappingChanged),
            if (mapping != buttonMappings.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class MappingRow extends StatelessWidget {
  const MappingRow({super.key, required this.mapping, required this.onChanged});

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MappingLabel(mapping: mapping),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, lineConstraints) {
                  final detail = switch (mapping.action) {
                    'key' => KeyDropdown(
                      mapping: mapping,
                      onChanged: onChanged,
                    ),
                    'mouseClick' => MouseButtonDropdown(
                      mapping: mapping,
                      onChanged: onChanged,
                    ),
                    _ => null,
                  };

                  if (detail == null) {
                    return ActionDropdown(
                      mapping: mapping,
                      onChanged: onChanged,
                    );
                  }

                  if (lineConstraints.maxWidth < 380) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ActionDropdown(mapping: mapping, onChanged: onChanged),
                        const SizedBox(height: 8),
                        detail,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ActionDropdown(
                          mapping: mapping,
                          onChanged: onChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: detail),
                    ],
                  );
                },
              ),
              if (mapping.action == 'key') ...[
                const SizedBox(height: 8),
                ModifierChips(mapping: mapping, onChanged: onChanged),
              ],
              const SizedBox(height: 8),
              HapticEffectLine(mapping: mapping, onChanged: onChanged),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 220, child: MappingLabel(mapping: mapping)),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          child: ActionDropdown(
                            mapping: mapping,
                            onChanged: onChanged,
                          ),
                        ),
                        if (mapping.action == 'key')
                          SizedBox(
                            width: 220,
                            child: KeyDropdown(
                              mapping: mapping,
                              onChanged: onChanged,
                            ),
                          ),
                        if (mapping.action == 'mouseClick')
                          SizedBox(
                            width: 180,
                            child: MouseButtonDropdown(
                              mapping: mapping,
                              onChanged: onChanged,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (mapping.action == 'key') ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 220),
                child: ModifierChips(mapping: mapping, onChanged: onChanged),
              ),
            ],
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 220),
              child: HapticEffectLine(mapping: mapping, onChanged: onChanged),
            ),
          ],
        );
      },
    );
  }
}

class MappingLabel extends StatelessWidget {
  const MappingLabel({super.key, required this.mapping});

  final BridgeMapping mapping;

  @override
  Widget build(BuildContext context) {
    return Text(
      mapping.controlLabel,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
}

class ActionDropdown extends StatelessWidget {
  const ActionDropdown({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('action-${mapping.id}-${mapping.action}'),
      initialValue: mapping.action,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Action',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'none', child: Text('Off')),
        DropdownMenuItem(value: 'key', child: Text('Key')),
        DropdownMenuItem(value: 'mouseClick', child: Text('Mouse click')),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(mapping.copyWith(action: value));
        }
      },
    );
  }
}

class KeyDropdown extends StatelessWidget {
  const KeyDropdown({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = keyOptionFor(mapping.keyCode);
    return DropdownButtonFormField<int>(
      key: ValueKey('key-${mapping.id}-${mapping.keyCode}'),
      initialValue: selected?.keyCode,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Key',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final option in keyOptions)
          DropdownMenuItem(value: option.keyCode, child: Text(option.label)),
      ],
      onChanged: (value) {
        final option = keyOptionFor(value);
        if (option != null) {
          onChanged(
            mapping.copyWith(keyCode: option.keyCode, keyLabel: option.label),
          );
        }
      },
    );
  }
}

class MouseButtonDropdown extends StatelessWidget {
  const MouseButtonDropdown({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('mouse-button-${mapping.id}-${mapping.mouseButton}'),
      initialValue: mouseButtonLabel(mapping.mouseButton) == null
          ? 'left'
          : mapping.mouseButton,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Button',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'left', child: Text('Left click')),
        DropdownMenuItem(value: 'right', child: Text('Right click')),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(mapping.copyWith(mouseButton: value));
        }
      },
    );
  }
}

class HapticEffectToggle extends StatelessWidget {
  const HapticEffectToggle({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Vibrate'),
        const SizedBox(width: 8),
        Switch(
          value: mapping.vibrate,
          onChanged: (value) => onChanged(mapping.copyWith(vibrate: value)),
        ),
      ],
    );
  }
}

class HapticEffectLine extends StatelessWidget {
  const HapticEffectLine({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(
          width: 88,
          child: Text('Haptics', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: HapticEffectToggle(
                  mapping: mapping,
                  onChanged: onChanged,
                ),
              ),
              if (mapping.vibrate)
                SizedBox(
                  width: 132,
                  child: HapticStyleDropdown(
                    mapping: mapping,
                    onChanged: onChanged,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class HapticStyleDropdown extends StatelessWidget {
  const HapticStyleDropdown({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Pattern',
      initialValue: mapping.hapticStyle,
      onSelected: (value) => onChanged(mapping.copyWith(hapticStyle: value)),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'pulse', child: Text('Pulse')),
        PopupMenuItem(value: 'engine', child: Text('Drive')),
        PopupMenuItem(value: 'gunshot', child: Text('Shoot')),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hapticStyleLabel(mapping.hapticStyle),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

String hapticStyleLabel(String style) {
  return switch (style) {
    'engine' => 'Drive',
    'gunshot' => 'Shoot',
    _ => 'Pulse',
  };
}

class ModifierChips extends StatelessWidget {
  const ModifierChips({
    super.key,
    required this.mapping,
    required this.onChanged,
  });

  final BridgeMapping mapping;
  final ValueChanged<BridgeMapping> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(
          width: 88,
          child: Text(
            'Modifiers',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final modifier in modifierOptions)
                FilterChip(
                  label: Text(modifier.label),
                  selected: mapping.modifiers.contains(modifier.id),
                  onSelected: (selected) {
                    final modifiers = [...mapping.modifiers];
                    selected
                        ? modifiers.add(modifier.id)
                        : modifiers.remove(modifier.id);
                    onChanged(mapping.copyWith(modifiers: modifiers));
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class NativeBridge {
  static const MethodChannel _method = MethodChannel('bridge_sense/control');
  static const EventChannel _events = EventChannel('bridge_sense/events');

  Stream<ControllerSnapshot> watch() {
    return _events.receiveBroadcastStream().map(ControllerSnapshot.fromDynamic);
  }

  Future<ControllerSnapshot> snapshot() async {
    try {
      final result = await _method.invokeMethod<dynamic>('getSnapshot');
      return ControllerSnapshot.fromDynamic(result);
    } on MissingPluginException {
      return ControllerSnapshot.empty();
    } on PlatformException {
      return ControllerSnapshot.empty();
    }
  }

  Future<void> setBridgeEnabled(bool enabled) async {
    await _invoke('setBridgeEnabled', enabled);
  }

  Future<ControllerSnapshot> setActiveProfile(String profileId) async {
    try {
      final result = await _method.invokeMethod<dynamic>(
        'setActiveProfile',
        profileId,
      );
      return ControllerSnapshot.fromDynamic(result);
    } on MissingPluginException {
      return ControllerSnapshot.empty();
    } on PlatformException {
      return ControllerSnapshot.empty();
    }
  }

  Future<void> setMappings(List<BridgeMapping> mappings) async {
    await _invoke(
      'setMappings',
      mappings.map((mapping) => mapping.toMap()).toList(growable: false),
    );
  }

  Future<void> setSettings(BridgeSettings settings) async {
    await _invoke('setSettings', settings.toMap());
  }

  Future<ControllerSnapshot> resetMappings() async {
    try {
      final result = await _method.invokeMethod<dynamic>('resetMappings');
      return ControllerSnapshot.fromDynamic(result);
    } on MissingPluginException {
      return ControllerSnapshot.empty();
    } on PlatformException {
      return ControllerSnapshot.empty();
    }
  }

  Future<void> requestAccessibility() async {
    await _invoke('requestAccessibility');
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _method.invokeMethod<dynamic>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

class ControllerSnapshot {
  const ControllerSnapshot({
    required this.connected,
    required this.controllerName,
    required this.productCategory,
    required this.controllerType,
    required this.activeProfileId,
    required this.activeProfileName,
    required this.connectedControllers,
    required this.supportedControlIds,
    required this.isDualSense,
    required this.hapticsAvailable,
    required this.adaptiveTriggersAvailable,
    required this.accessibilityTrusted,
    required this.bridgeEnabled,
    required this.lastAction,
    required this.inputs,
    required this.mappings,
    required this.settings,
  });

  factory ControllerSnapshot.empty() {
    return ControllerSnapshot(
      connected: false,
      controllerName: 'No controller',
      productCategory: 'Unknown',
      controllerType: 'none',
      activeProfileId: 'dualSense',
      activeProfileName: 'DualSense',
      connectedControllers: const [],
      supportedControlIds: defaultSupportedControlIds,
      isDualSense: false,
      hapticsAvailable: false,
      adaptiveTriggersAvailable: false,
      accessibilityTrusted: false,
      bridgeEnabled: true,
      lastAction: '',
      inputs: const {},
      mappings: defaultMappings,
      settings: const BridgeSettings(
        pointerSpeed: 22,
        scrollSpeed: 14,
        deadZone: 0.12,
      ),
    );
  }

  factory ControllerSnapshot.fromDynamic(dynamic value) {
    final map = asStringMap(value);
    final mappingValues = asList(map['mappings'])
        .map(BridgeMapping.fromDynamic)
        .whereType<BridgeMapping>()
        .toList(growable: false);

    return ControllerSnapshot(
      connected: asBool(map['connected']),
      controllerName: asString(map['controllerName'], 'No controller'),
      productCategory: asString(map['productCategory'], 'Unknown'),
      controllerType: asString(map['controllerType'], 'none'),
      activeProfileId: asString(map['activeProfileId'], 'dualSense'),
      activeProfileName: asString(map['activeProfileName'], 'DualSense'),
      connectedControllers: asList(map['connectedControllers'])
          .map(ConnectedController.fromDynamic)
          .whereType<ConnectedController>()
          .toList(growable: false),
      supportedControlIds: asList(
        map['supportedControlIds'],
      ).map((item) => item.toString()).toSet(),
      isDualSense: asBool(map['isDualSense']),
      hapticsAvailable: asBool(map['hapticsAvailable']),
      adaptiveTriggersAvailable: asBool(map['adaptiveTriggersAvailable']),
      accessibilityTrusted: asBool(map['accessibilityTrusted']),
      bridgeEnabled: asBool(map['bridgeEnabled'], true),
      lastAction: asString(map['lastAction']),
      inputs: asStringMap(
        map['inputs'],
      ).map((key, value) => MapEntry(key, asDouble(value))),
      mappings: mappingValues.isEmpty ? defaultMappings : mappingValues,
      settings: BridgeSettings.fromDynamic(map['settings']),
    );
  }

  final bool connected;
  final String controllerName;
  final String productCategory;
  final String controllerType;
  final String activeProfileId;
  final String activeProfileName;
  final List<ConnectedController> connectedControllers;
  final Set<String> supportedControlIds;
  final bool isDualSense;
  final bool hapticsAvailable;
  final bool adaptiveTriggersAvailable;
  final bool accessibilityTrusted;
  final bool bridgeEnabled;
  final String lastAction;
  final Map<String, double> inputs;
  final List<BridgeMapping> mappings;
  final BridgeSettings settings;

  ControllerSnapshot copyWith({
    bool? connected,
    String? controllerName,
    String? productCategory,
    String? controllerType,
    String? activeProfileId,
    String? activeProfileName,
    List<ConnectedController>? connectedControllers,
    Set<String>? supportedControlIds,
    bool? isDualSense,
    bool? hapticsAvailable,
    bool? adaptiveTriggersAvailable,
    bool? accessibilityTrusted,
    bool? bridgeEnabled,
    String? lastAction,
    Map<String, double>? inputs,
    List<BridgeMapping>? mappings,
    BridgeSettings? settings,
  }) {
    return ControllerSnapshot(
      connected: connected ?? this.connected,
      controllerName: controllerName ?? this.controllerName,
      productCategory: productCategory ?? this.productCategory,
      controllerType: controllerType ?? this.controllerType,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      activeProfileName: activeProfileName ?? this.activeProfileName,
      connectedControllers: connectedControllers ?? this.connectedControllers,
      supportedControlIds: supportedControlIds ?? this.supportedControlIds,
      isDualSense: isDualSense ?? this.isDualSense,
      hapticsAvailable: hapticsAvailable ?? this.hapticsAvailable,
      adaptiveTriggersAvailable:
          adaptiveTriggersAvailable ?? this.adaptiveTriggersAvailable,
      accessibilityTrusted: accessibilityTrusted ?? this.accessibilityTrusted,
      bridgeEnabled: bridgeEnabled ?? this.bridgeEnabled,
      lastAction: lastAction ?? this.lastAction,
      inputs: inputs ?? this.inputs,
      mappings: mappings ?? this.mappings,
      settings: settings ?? this.settings,
    );
  }

  BridgeMapping mappingFor(String id) {
    return mappings.firstWhere(
      (mapping) => mapping.id == id,
      orElse: () => defaultMappings.firstWhere((mapping) => mapping.id == id),
    );
  }

  bool supportsControl(String id) {
    return supportedControlIds.isEmpty || supportedControlIds.contains(id);
  }

  String get connectedControllerSummary {
    final count = connectedControllers.length;
    if (count == 0) {
      return 'None';
    }
    if (count == 1) {
      return '1 connected';
    }
    return '$count connected';
  }
}

class ConnectedController {
  const ConnectedController({
    required this.id,
    required this.name,
    required this.productCategory,
    required this.controllerType,
    required this.profileName,
    required this.active,
  });

  static ConnectedController? fromDynamic(dynamic value) {
    final map = asStringMap(value);
    if (map.isEmpty) {
      return null;
    }
    return ConnectedController(
      id: asString(map['id']),
      name: asString(map['name'], 'Controller'),
      productCategory: asString(map['productCategory'], 'Unknown'),
      controllerType: asString(map['controllerType'], 'generic'),
      profileName: asString(map['profileName'], 'Generic'),
      active: asBool(map['active']),
    );
  }

  final String id;
  final String name;
  final String productCategory;
  final String controllerType;
  final String profileName;
  final bool active;
}

class ControllerProfileOption {
  const ControllerProfileOption({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;
  final IconData icon;
}

const controllerProfileOptions = [
  ControllerProfileOption(
    id: 'dualSense',
    name: 'DualSense',
    icon: Icons.sports_esports,
  ),
  ControllerProfileOption(
    id: 'switchPro',
    name: 'Switch Pro',
    icon: Icons.sports_esports,
  ),
  ControllerProfileOption(
    id: 'xbox',
    name: 'Xbox',
    icon: Icons.sports_esports,
  ),
  ControllerProfileOption(id: 'generic', name: 'Generic', icon: Icons.gamepad),
];

class BridgeSettings {
  const BridgeSettings({
    required this.pointerSpeed,
    required this.scrollSpeed,
    required this.deadZone,
  });

  factory BridgeSettings.fromDynamic(dynamic value) {
    final map = asStringMap(value);
    return BridgeSettings(
      pointerSpeed: asDouble(map['pointerSpeed'], 22),
      scrollSpeed: asDouble(map['scrollSpeed'], 14),
      deadZone: asDouble(map['deadZone'], 0.12),
    );
  }

  final double pointerSpeed;
  final double scrollSpeed;
  final double deadZone;

  BridgeSettings copyWith({
    double? pointerSpeed,
    double? scrollSpeed,
    double? deadZone,
  }) {
    return BridgeSettings(
      pointerSpeed: pointerSpeed ?? this.pointerSpeed,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      deadZone: deadZone ?? this.deadZone,
    );
  }

  Map<String, Object> toMap() {
    return {
      'pointerSpeed': pointerSpeed,
      'scrollSpeed': scrollSpeed,
      'deadZone': deadZone,
    };
  }
}

class BridgeMapping {
  const BridgeMapping({
    required this.id,
    required this.controlLabel,
    required this.action,
    required this.label,
    required this.keyCode,
    required this.keyLabel,
    this.mouseButton = 'left',
    required this.modifiers,
    required this.vibrate,
    required this.hapticStyle,
  });

  factory BridgeMapping.fromDynamic(dynamic value) {
    final map = asStringMap(value);
    final rawAction = asString(map['action'], 'none');
    final action = rawAction == 'haptic' ? 'none' : rawAction;
    return BridgeMapping(
      id: asString(map['id']),
      controlLabel: asString(map['controlLabel']),
      action: {'none', 'key', 'mouseClick', 'cursor', 'scroll'}.contains(action)
          ? action
          : 'none',
      label: asString(map['label']),
      keyCode: asNullableInt(map['keyCode']),
      keyLabel: asString(map['keyLabel']),
      mouseButton: asMouseButton(map['mouseButton']),
      modifiers: asList(
        map['modifiers'],
      ).map((item) => item.toString()).toList(growable: false),
      vibrate: asBool(map['vibrate']) || rawAction == 'haptic',
      hapticStyle: asString(map['hapticStyle'], 'pulse'),
    );
  }

  final String id;
  final String controlLabel;
  final String action;
  final String label;
  final int? keyCode;
  final String keyLabel;
  final String mouseButton;
  final List<String> modifiers;
  final bool vibrate;
  final String hapticStyle;

  bool get isMotionControl =>
      id == 'leftStick' || id == 'rightStick' || id == 'touchpadMotion';

  BridgeMapping copyWith({
    String? action,
    String? label,
    int? keyCode,
    String? keyLabel,
    String? mouseButton,
    List<String>? modifiers,
    bool? vibrate,
    String? hapticStyle,
  }) {
    return BridgeMapping(
      id: id,
      controlLabel: controlLabel,
      action: action ?? this.action,
      label: label ?? this.label,
      keyCode: keyCode ?? this.keyCode,
      keyLabel: keyLabel ?? this.keyLabel,
      mouseButton: mouseButton ?? this.mouseButton,
      modifiers: modifiers ?? this.modifiers,
      vibrate: vibrate ?? this.vibrate,
      hapticStyle: hapticStyle ?? this.hapticStyle,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'controlLabel': controlLabel,
      'action': action,
      'label': label,
      'keyCode': keyCode,
      'keyLabel': keyLabel,
      'mouseButton': mouseButton,
      'modifiers': modifiers,
      'vibrate': vibrate,
      'hapticStyle': hapticStyle,
    };
  }
}

class KeyOption {
  const KeyOption(this.label, this.keyCode);

  final String label;
  final int keyCode;
}

class ModifierOption {
  const ModifierOption(this.id, this.label);

  final String id;
  final String label;
}

const modifierOptions = [
  ModifierOption('command', 'Command'),
  ModifierOption('shift', 'Shift'),
  ModifierOption('option', 'Option'),
  ModifierOption('control', 'Control'),
];

String asMouseButton(dynamic value) {
  final button = asString(value, 'left');
  return mouseButtonLabel(button) == null ? 'left' : button;
}

String? mouseButtonLabel(String button) {
  return switch (button) {
    'left' => 'Left click',
    'right' => 'Right click',
    _ => null,
  };
}

const keyOptions = [
  KeyOption('Esc', 53),
  KeyOption('Return', 36),
  KeyOption('Space', 49),
  KeyOption('Tab', 48),
  KeyOption('Delete', 51),
  KeyOption('Forward Delete', 117),
  KeyOption('Left Arrow', 123),
  KeyOption('Right Arrow', 124),
  KeyOption('Down Arrow', 125),
  KeyOption('Up Arrow', 126),
  KeyOption('A', 0),
  KeyOption('B', 11),
  KeyOption('C', 8),
  KeyOption('D', 2),
  KeyOption('E', 14),
  KeyOption('F', 3),
  KeyOption('G', 5),
  KeyOption('H', 4),
  KeyOption('I', 34),
  KeyOption('J', 38),
  KeyOption('K', 40),
  KeyOption('L', 37),
  KeyOption('M', 46),
  KeyOption('N', 45),
  KeyOption('O', 31),
  KeyOption('P', 35),
  KeyOption('Q', 12),
  KeyOption('R', 15),
  KeyOption('S', 1),
  KeyOption('T', 17),
  KeyOption('U', 32),
  KeyOption('V', 9),
  KeyOption('W', 13),
  KeyOption('X', 7),
  KeyOption('Y', 16),
  KeyOption('Z', 6),
  KeyOption('0', 29),
  KeyOption('1', 18),
  KeyOption('2', 19),
  KeyOption('3', 20),
  KeyOption('4', 21),
  KeyOption('5', 23),
  KeyOption('6', 22),
  KeyOption('7', 26),
  KeyOption('8', 28),
  KeyOption('9', 25),
  KeyOption('F1', 122),
  KeyOption('F2', 120),
  KeyOption('F3', 99),
  KeyOption('F4', 118),
  KeyOption('F5', 96),
  KeyOption('F6', 97),
  KeyOption('F7', 98),
  KeyOption('F8', 100),
  KeyOption('F9', 101),
  KeyOption('F10', 109),
  KeyOption('F11', 103),
  KeyOption('F12', 111),
];

String controllerTypeLabel(String type) {
  return switch (type) {
    'dualSense' => 'DualSense',
    'switchPro' => 'Switch Pro',
    'xbox' => 'Xbox',
    'generic' => 'Generic',
    _ => 'None',
  };
}

KeyOption? keyOptionFor(int? keyCode) {
  if (keyCode == null) {
    return null;
  }
  for (final option in keyOptions) {
    if (option.keyCode == keyCode) {
      return option;
    }
  }
  return null;
}

const defaultSupportedControlIds = {
  'leftStick',
  'rightStick',
  'touchpadMotion',
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
  'touchpad',
};

const defaultMappings = [
  BridgeMapping(
    id: 'leftStick',
    controlLabel: 'L stick',
    action: 'cursor',
    label: 'Cursor',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'rightStick',
    controlLabel: 'R stick',
    action: 'scroll',
    label: 'Scroll',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'touchpadMotion',
    controlLabel: 'Touchpad move',
    action: 'cursor',
    label: 'Mouse move',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'l2',
    controlLabel: 'L2',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'r2',
    controlLabel: 'R2',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'l1',
    controlLabel: 'L1',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'r1',
    controlLabel: 'R1',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'cross',
    controlLabel: 'Cross / A',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'circle',
    controlLabel: 'Circle / B',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'square',
    controlLabel: 'Square / X',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'triangle',
    controlLabel: 'Triangle / Y',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'dpadUp',
    controlLabel: 'D-pad up',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'dpadDown',
    controlLabel: 'D-pad down',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'dpadLeft',
    controlLabel: 'D-pad left',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'dpadRight',
    controlLabel: 'D-pad right',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'leftStickButton',
    controlLabel: 'L3',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'rightStickButton',
    controlLabel: 'R3',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'menu',
    controlLabel: 'Menu',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'options',
    controlLabel: 'Options',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'home',
    controlLabel: 'PS / Home',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
  BridgeMapping(
    id: 'touchpad',
    controlLabel: 'Touchpad click',
    action: 'none',
    label: '',
    keyCode: null,
    keyLabel: '',
    modifiers: [],
    vibrate: false,
    hapticStyle: 'pulse',
  ),
];

Map<String, dynamic> asStringMap(dynamic value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<dynamic> asList(dynamic value) {
  return value is List ? value : const [];
}

String asString(dynamic value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

bool asBool(dynamic value, [bool fallback = false]) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

double asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

int? asNullableInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

extension InputValueLookup on Map<String, double> {
  double value(String key) => this[key] ?? 0;
}
