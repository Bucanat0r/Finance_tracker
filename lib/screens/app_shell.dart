import 'package:flutter/material.dart';

import 'budgets_page.dart';
import 'home_page.dart';

/// The frame around the app's main screens: a bottom bar to switch between
/// them. When we add Reports and Settings later, they become two more tabs
/// here and nothing else has to change.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // The screens, in the same order as the bottom bar items below.
  final _pages = const [HomePage(), BudgetsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every tab alive in the background, so switching
      // tabs does not reset a screen or reload its data.
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Budgets',
          ),
        ],
      ),
    );
  }
}
