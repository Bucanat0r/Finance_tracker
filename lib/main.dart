import 'package:flutter/material.dart';

import 'screens/app_lock_gate.dart';
import 'screens/app_shell.dart';

void main() {
  // Required before using plugins (like the one that finds the database
  // folder) at startup.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finance Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // "builder" wraps the app's navigator, so the lock screen sits ABOVE
      // every screen and popup. If we wrapped only the home screen instead,
      // any screen you had pushed on top (like the Add form) would hide the
      // lock.
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
      home: const AppShell(),
    );
  }
}
