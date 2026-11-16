import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/backup_queries.dart';
import '../data/backup_service.dart';
import '../data/database_instance.dart';
import '../utils/formatters.dart';

/// Back up, restore, and export your data.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  DateTime? _lastBackup;
  bool _loaded = false;

  // True while a job runs, so buttons cannot be pressed twice.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final last = await BackupService.lastBackupAt();
    if (!mounted) return;
    setState(() {
      _lastBackup = last;
      _loaded = true;
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Runs a job with the busy flag on, and reports any error in words.
  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUp() => _run(() async {
    final shared = await BackupService.shareBackup();
    if (!mounted) return;
    if (shared) {
      await _refresh();
      _snack('Backup shared. Make sure it was actually saved somewhere.');
    }
  });

  Future<void> _exportCsv() => _run(() async {
    await BackupService.shareCsv();
  });

  Future<void> _restore() => _run(() async {
    // 1. Let the user pick ONE file. In the current file_picker, the
    //    single-file picker is FilePicker.pickFile(). It returns null if
    //    the user cancels. (Older versions used FilePicker.platform
    //    .pickFiles(withData: true), which no longer exists.)
    final picked = await FilePicker.pickFile();
    if (picked == null) return; // Cancelled.

    // 2. Read the file's contents. The file is read only when we ask,
    //    which is why this is a separate step. No storage permission is
    //    needed, because the user chose the file themselves.
    final List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      if (mounted) _snack('Could not read that file.');
      return;
    }

    // 3. Check it is really one of our backups BEFORE touching any data.
    final Map<String, dynamic> data;
    final BackupSummary summary;
    try {
      data = validateBackup(jsonDecode(utf8.decode(bytes)));
      summary = summarizeBackup(data);
    } on BackupException catch (e) {
      if (mounted) _snack(e.message);
      return;
    } catch (_) {
      if (mounted) _snack('That file is not a Finance Tracker backup.');
      return;
    }

    if (!mounted) return;

    // 4. Show what is inside and ask for a clear yes.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Text(
          'This backup'
          '${summary.exportedAt == null ? '' : ' from ${formatDate(summary.exportedAt!)}'}'
          ' contains ${summary.accounts} accounts, '
          '${summary.transactions} transactions, '
          '${summary.categories} categories and ${summary.budgets} budgets.\n\n'
          'Everything currently in the app will be REPLACED. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 5. Restore. If anything fails, the database rolls back and your
    //    current data is untouched.
    try {
      await db.restoreBackup(data);
      if (mounted) _snack('Backup restored.');
    } catch (_) {
      if (mounted) {
        _snack(
          'The backup could not be restored, so nothing was changed. '
          'The file may be damaged.',
        );
      }
    }
  });

  /// "today", "yesterday", "3 days ago".
  String _ago(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _lastBackup;

    // Nudge: no backup at all, or an old one, is shown in the error colour.
    final stale = last == null || DateTime.now().difference(last).inDays >= 14;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & export')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          stale ? Icons.warning_amber : Icons.check_circle,
                          color: stale ? scheme.error : Colors.green.shade700,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            last == null
                                ? 'You have never backed up.'
                                : 'Last backup: ${formatDate(last)} (${_ago(last)})',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Back up now'),
                  subtitle: const Text(
                    'Save a copy to Google Drive, Telegram, email, anywhere.',
                  ),
                  enabled: !_busy,
                  onTap: _backUp,
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restore from a backup'),
                  subtitle: const Text('Replaces everything in the app.'),
                  enabled: !_busy,
                  onTap: _restore,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const Text('Export transactions (CSV)'),
                  subtitle: const Text(
                    'For Excel or Google Sheets. Cannot be restored into the app.',
                  ),
                  enabled: !_busy,
                  onTap: _exportCsv,
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Backup files are NOT encrypted. Anyone who gets the file '
                    'can read your finances, so keep it somewhere private: '
                    'your own Google Drive, or a chat with yourself.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}
