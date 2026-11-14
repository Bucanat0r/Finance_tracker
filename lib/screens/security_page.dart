import 'package:flutter/material.dart';

import '../security/pin_service.dart';
import 'pin_setup_page.dart';

/// The "App lock" settings page: turn the PIN on, change it, or remove it.
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  // Null until we have checked whether a PIN is set.
  bool? _hasPin;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final has = await PinService.hasPin();
    if (!mounted) return;
    setState(() => _hasPin = has);
  }

  Future<void> _open(PinSetupMode mode) async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PinSetupPage(mode: mode)),
    );

    if (!mounted) return;
    await _refresh();
    if (!mounted || done != true) return;

    final text = switch (mode) {
      PinSetupMode.set => 'PIN is on.',
      PinSetupMode.change => 'PIN changed.',
      PinSetupMode.remove => 'PIN removed.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _hasPin;

    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: Icon(hasPin ? Icons.lock : Icons.lock_open),
                  title: Text(hasPin ? 'PIN is on' : 'PIN is off'),
                  subtitle: Text(
                    hasPin
                        ? 'The app asks for it when you open it, and when you '
                              'come back after ${relockAfter.inSeconds} seconds away.'
                        : 'Anyone who opens the app can see your finances.',
                  ),
                ),
                const Divider(),
                if (!hasPin)
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Set a PIN'),
                    onTap: () => _open(PinSetupMode.set),
                  )
                else ...[
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Change PIN'),
                    onTap: () => _open(PinSetupMode.change),
                  ),
                  ListTile(
                    leading: const Icon(Icons.no_encryption_outlined),
                    title: const Text('Remove PIN'),
                    onTap: () => _open(PinSetupMode.remove),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'There is no way to recover a forgotten PIN. The only way '
                    'back in is to clear the app\'s data, which deletes '
                    'everything in it. Backups will protect you from that.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}
