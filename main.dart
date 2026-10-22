import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const QuestModBridgeApp());
}

const bridge = MethodChannel('quest_mod_bridge');
const triggerEvents = EventChannel('quest_mod_bridge/events');

class QuestModBridgeApp extends StatelessWidget {
  const QuestModBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quest Mod Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B7CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101116),
        cardTheme: CardTheme(
          color: const Color(0xFF1B1D26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF13151C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const ModHomePage(),
    );
  }
}

enum ActivationMode {
  rightTrigger,
  leftTrigger,
  manual,
  alwaysOn,
}

class ModItem {
  ModItem({
    required this.name,
    required this.description,
    required this.icon,
  });

  final String name;
  final String description;
  final IconData icon;

  bool enabled = false;
  bool active = false;
  ActivationMode mode = ActivationMode.rightTrigger;

  String command = '';
  String resetCommand = '';
}

class ModHomePage extends StatefulWidget {
  const ModHomePage({super.key});

  @override
  State<ModHomePage> createState() => _ModHomePageState();
}

class _ModHomePageState extends State<ModHomePage> {
  final ipController = TextEditingController();
  final pairingPortController = TextEditingController();
  final connectionPortController = TextEditingController();
  final pairingCodeController = TextEditingController();
  final commandController = TextEditingController();
  final resetController = TextEditingController();

  final List<ModItem> mods = [
    ModItem(
      name: 'Long Arms',
      description: 'Configure the Long Arms command.',
      icon: Icons.open_with,
    ),
    ModItem(
      name: 'Fast Pull',
      description: 'Configure the Fast Pull command.',
      icon: Icons.speed,
    ),
    ModItem(
      name: 'Smooth Fly',
      description: 'Configure the Smooth Fly command.',
      icon: Icons.flight,
    ),
    ModItem(
      name: 'Teleport',
      description: 'Configure the Teleport command.',
      icon: Icons.near_me,
    ),
    ModItem(
      name: 'Backflip',
      description: 'Configure the Backflip command.',
      icon: Icons.rotate_left,
    ),
    ModItem(
      name: 'Front Flip',
      description: 'Configure the Front Flip command.',
      icon: Icons.rotate_right,
    ),
    ModItem(
      name: 'Fly Upward',
      description: 'Configure the Fly Upward command.',
      icon: Icons.arrow_upward,
    ),
  ];

  int selectedIndex = 0;
  bool connected = false;
  bool busy = false;
  bool guardianEnabled = true;

  double rightTrigger = 0;
  double leftTrigger = 0;
  bool nativeInputAvailable = false;

  String status = 'Not connected';
  String inputStatus = 'Waiting for native controller support';

  final List<String> logs = [];
  StreamSubscription? triggerSubscription;

  ModItem get selectedMod => mods[selectedIndex];

  @override
  void initState() {
    super.initState();
    loadCommands();
    listenForTriggers();
  }

  @override
  void dispose() {
    triggerSubscription?.cancel();
    ipController.dispose();
    pairingPortController.dispose();
    connectionPortController.dispose();
    pairingCodeController.dispose();
    commandController.dispose();
    resetController.dispose();
    super.dispose();
  }

  void listenForTriggers() {
    triggerSubscription = triggerEvents.receiveBroadcastStream().listen(
      (event) {
        final data = Map<String, dynamic>.from(event as Map);

        rightTrigger =
            (data['rightTrigger'] as num?)?.toDouble() ?? 0;
        leftTrigger =
            (data['leftTrigger'] as num?)?.toDouble() ?? 0;

        nativeInputAvailable = true;
        inputStatus = 'Receiving native input events';

        processTrigger(
          ActivationMode.rightTrigger,
          rightTrigger,
        );
        processTrigger(
          ActivationMode.leftTrigger,
          leftTrigger,
        );

        if (mounted) setState(() {});
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          nativeInputAvailable = false;
          inputStatus = 'Native input bridge unavailable';
        });
      },
    );
  }

  void processTrigger(ActivationMode mode, double value) {
    for (final mod in mods) {
      if (!mod.enabled || mod.mode != mode) continue;

      if (value >= 0.55 && !mod.active) {
        mod.active = true;
        log('${mod.name}: trigger pressed');
        runCommand(mod.command, '${mod.name} activation');
      } else if (value <= 0.35 && mod.active) {
        mod.active = false;
        log('${mod.name}: trigger released');

        if (mod.resetCommand.trim().isNotEmpty) {
          runCommand(
            mod.resetCommand,
            '${mod.name} reset',
          );
        }
      }
    }
  }

  void loadCommands() {
    commandController.text = selectedMod.command;
    resetController.text = selectedMod.resetCommand;
  }

  void selectMod(int index) {
    setState(() {
      selectedIndex = index;
      loadCommands();
    });
  }

  void saveCommands() {
    setState(() {
      selectedMod.command = commandController.text.trim();
      selectedMod.resetCommand = resetController.text.trim();
    });
    log('${selectedMod.name}: commands saved for this session');
    toast('Commands saved for this session');
  }

  Future<void> pairAdb() async {
    final ip = ipController.text.trim();
    final port = int.tryParse(pairingPortController.text.trim());
    final code = pairingCodeController.text.trim();

    if (ip.isEmpty || port == null || code.isEmpty) {
      toast('Enter the IP, pairing port, and pairing code.');
      return;
    }

    setState(() {
      busy = true;
      status = 'Pairing...';
    });

    try {
      final result = await bridge.invokeMethod(
        'pairWirelessAdb',
        {
          'ip': ip,
          'pairingPort': port,
          'pairingCode': code,
        },
      );

      final success =
          result is Map && result['success'] == true;

      setState(() {
        status = success ? 'Paired' : 'Pairing failed';
      });

      log('Pairing result: $result');
    } on PlatformException catch (e) {
      setState(() => status = 'Native ADB unavailable');
      log('Pairing error: ${e.message}');
      toast('ADB native implementation is not installed.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connectAdb() async {
    final ip = ipController.text.trim();
    final port = int.tryParse(connectionPortController.text.trim());

    if (ip.isEmpty || port == null) {
      toast('Enter the IP address and connection port.');
      return;
    }

    setState(() {
      busy = true;
      status = 'Connecting...';
    });

    try {
      final result = await bridge.invokeMethod(
        'connectWirelessAdb',
        {
          'ip': ip,
          'connectionPort': port,
        },
      );

      final success =
          result is Map && result['success'] == true;

      setState(() {
        connected = success;
        status = success ? 'Connected' : 'Connection failed';
      });

      log('Connection result: $result');
    } on PlatformException catch (e) {
      setState(() {
        connected = false;
        status = 'Native ADB unavailable';
      });
      log('Connection error: ${e.message}');
      toast('ADB native implementation is not installed.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnectAdb() async {
    try {
      await bridge.invokeMethod('disconnectWirelessAdb');
    } catch (_) {
      log('Native disconnect method unavailable');
    }

    setState(() {
      connected = false;
      status = 'Disconnected';

      for (final mod in mods) {
        mod.active = false;
      }
    });

    log('ADB disconnected');
  }

  Future<void> runCommand(
    String command,
    String label,
  ) async {
    if (command.trim().isEmpty) {
      log('$label: no command configured');
      return;
    }

    if (!connected) {
      log('$label: not connected to ADB');
      return;
    }

    try {
      final result = await bridge.invokeMethod(
        'runShellCommand',
        {'command': command.trim()},
      );

      log('$label result: $result');
    } on PlatformException catch (e) {
      log('$label failed: ${e.message}');
    }
  }

  Future<void> toggleGuardian(bool value) async {
    // UI placeholder: it does not disable Quest Guardian.
    try {
      final result = await bridge.invokeMethod(
        'setBoundaryEnabled',
        {'enabled': value},
      );

      if (result is Map && result['supported'] == true) {
        setState(() => guardianEnabled = value);
        log('Boundary setting updated by native bridge');
      } else {
        toast('Guardian control is not implemented.');
        log('Boundary control unsupported');
      }
    } on PlatformException {
      toast('Guardian control is not implemented.');
      log('Boundary control unavailable');
    }
  }

  void toggleMod(ModItem mod, bool value) {
    setState(() {
      mod.enabled = value;

      if (!value && mod.active) {
        mod.active = false;

        if (mod.resetCommand.trim().isNotEmpty) {
          runCommand(mod.resetCommand, '${mod.name} reset');
        }
      }
    });

    log('${mod.name}: ${value ? 'enabled' : 'disabled'}');
  }

  String modeName(ActivationMode mode) {
    switch (mode) {
      case ActivationMode.rightTrigger:
        return 'Right Trigger (hold)';
      case ActivationMode.leftTrigger:
        return 'Left Trigger (hold)';
      case ActivationMode.manual:
        return 'Manual only';
      case ActivationMode.alwaysOn:
        return 'Always On (manual activation)';
    }
  }

  void log(String message) {
    if (!mounted) return;

    setState(() {
      logs.insert(
        0,
        '${TimeOfDay.now().format(context)}  $message',
      );

      if (logs.length > 80) {
        logs.removeLast();
      }
    });
  }

  void toast(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quest Mod Bridge'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                avatar: Icon(
                  connected ? Icons.link : Icons.link_off,
                  size: 17,
                ),
                label: Text(status),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            buildConnectionCard(),
            const SizedBox(height: 12),
            buildTriggerCard(),
            const SizedBox(height: 16),
            const Text(
              'YOUR MODS',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            buildModGrid(),
            const SizedBox(height: 12),
            buildSelectedModCard(),
            const SizedBox(height: 12),
            buildGuardianCard(),
            const SizedBox(height: 12),
            buildLogsCard(),
            const SizedBox(height: 20),
            const Text(
              'Important: this Flutter UI does not implement native ADB, '
              'global Quest trigger detection, or Guardian control. '
              'A native Android implementation is required.',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wifi_tethering),
                SizedBox(width: 8),
                Text(
                  'Wireless ADB Setup',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Find these values under Wireless Debugging on your Quest. '
              'Pairing and connection use different ports.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Quest IP address',
                hintText: '192.168.1.25',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pairingPortController,
              decoration: const InputDecoration(
                labelText: 'Pairing port',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pairingCodeController,
              decoration: const InputDecoration(
                labelText: 'Six-digit pairing code',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : pairAdb,
                icon: const Icon(Icons.key),
                label: const Text('Pair Wireless ADB'),
              ),
            ),
            const Divider(height: 28),
            TextField(
              controller: connectionPortController,
              decoration: const InputDecoration(
                labelText: 'Connection port',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy || connected ? null : connectAdb,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: connected ? disconnectAdb : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildTriggerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controller Trigger Status',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              inputStatus,
              style: TextStyle(
                color: nativeInputAvailable
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 14),
            triggerMeter('Right Trigger', rightTrigger),
            const SizedBox(height: 12),
            triggerMeter('Left Trigger', leftTrigger),
            const SizedBox(height: 8),
            const Text(
              'The meters update only if a native implementation sends '
              'controller events to this Flutter app.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget triggerMeter(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${(value * 100).round()}%'),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 8,
        ),
      ],
    );
  }

  Widget buildModGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mods.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final mod = mods[index];

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => selectMod(index),
          child: Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: selectedIndex == index
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(mod.icon, size: 25),
                      const Spacer(),
                      Switch(
                        value: mod.enabled,
                        onChanged: (value) => toggleMod(mod, value),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    mod.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mod.active
                        ? 'Active'
                        : mod.enabled
                            ? 'Enabled'
                            : 'Disabled',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildSelectedModCard() {
    final mod = selectedMod;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mod.name,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              mod.description,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable this mod'),
              value: mod.enabled,
              onChanged: (value) => toggleMod(mod, value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ActivationMode>(
              value: mod.mode,
              decoration: const InputDecoration(
                labelText: 'Activation method',
              ),
              items: ActivationMode.values.map((mode) {
                return DropdownMenuItem(
                  value: mode,
                  child: Text(modeName(mode)),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => mod.mode = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commandController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Activation command',
                hintText: 'Paste the verified command here',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: resetController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reset command on trigger release',
                hintText: 'Paste the reset command, if available',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: saveCommands,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Commands'),
                ),
                OutlinedButton.icon(
                  onPressed: connected
                      ? () {
                          saveCommands();
                          runCommand(
                            mod.command,
                            '${mod.name} test',
                          );
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Test Command'),
                ),
                OutlinedButton.icon(
                  onPressed: connected &&
                          mod.resetCommand.trim().isNotEmpty
                      ? () => runCommand(
                            resetController.text,
                            '${mod.name} reset test',
                          )
                      : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Test Reset'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Only use commands you have verified for your device and game. '
              'Some system properties require permissions and may not work.',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildGuardianCard() {
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.shield_outlined),
        title: const Text('Guardian / Boundary'),
        subtitle: const Text(
          'Placeholder only. This switch cannot change Quest Guardian '
          'without a supported native method.',
        ),
        value: guardianEnabled,
        onChanged: toggleGuardian,
      ),
    );
  }

  Widget buildLogsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Activity Log',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => logs.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              const Text(
                'No activity yet.',
                style: TextStyle(color: Colors.white60),
              )
            else
              ...logs.take(15).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        entry,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}