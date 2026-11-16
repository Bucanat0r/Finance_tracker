import 'package:flutter/material.dart';

import 'accounts_page.dart';
import 'backup_page.dart';
import 'categories_page.dart';
import 'security_page.dart';

/// The "More" tab: a menu for everything that is not a main screen.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Accounts'),
            subtitle: const Text('Balances, names and opening balances'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: const Text('Add, rename or delete categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text('Protect the app with a PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SecurityPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & export'),
            subtitle: const Text(
              'Back up, restore, or export to a spreadsheet',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupPage()),
            ),
          ),
        ],
      ),
    );
  }
}
