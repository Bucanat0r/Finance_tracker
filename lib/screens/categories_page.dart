import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/database_instance.dart';
import '../data/manage_queries.dart';
import '../data/tables.dart';

/// Add, rename and delete your own categories.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  // Created once so the stream is not restarted on every rebuild.
  late final Stream<List<Category>> _stream = db.watchAllCategories();

  /// Asks before deleting, and says exactly what will happen, because the
  /// consequences are not obvious: your transactions are kept, but budgets
  /// for this category disappear.
  Future<void> _confirmDelete(Category c) async {
    final count = await db.transactionCountForCategory(c.id);
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: Text(
          count == 0
              ? 'No transactions use this category. Any budgets set for it '
                    'will be removed.'
              : '$count transaction${count == 1 ? '' : 's'} will keep their '
                    'amounts but lose this category. Any budgets set for it '
                    'will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) await db.deleteCategory(c.id);
  }

  void _openDialog({Category? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: () => _openDialog(),
      ),
      body: StreamBuilder<List<Category>>(
        stream: _stream,
        builder: (context, snapshot) {
          final all = snapshot.data;
          if (all == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // Split into the two groups the app cares about.
          final expenses = all.where((c) => c.kind == TxnKind.expense).toList();
          final incomes = all.where((c) => c.kind == TxnKind.income).toList();

          return ListView(
            // Space at the bottom so the Add button never covers the last row.
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _header('Expenses'),
              for (final c in expenses) _tile(c),
              _header('Income'),
              for (final c in incomes) _tile(c),
            ],
          );
        },
      ),
    );
  }

  Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _tile(Category c) {
    return ListTile(
      title: Text(c.name),
      onTap: () => _openDialog(existing: c),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(c),
      ),
    );
  }
}

/// One popup for both adding a category and renaming one.
/// When [existing] is given we are renaming (the type cannot change, since
/// existing transactions rely on it); otherwise we are adding a new one.
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.existing});

  final Category? existing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _ctrl;
  TxnKind _kind = TxnKind.expense;
  String? _error;

  bool get _isRenaming => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?.name ?? '');
    if (widget.existing != null) _kind = widget.existing!.kind;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }

    // Friendly check first, instead of letting the database reject it.
    final taken = await db.categoryNameTaken(
      name,
      _kind,
      exceptId: widget.existing?.id,
    );
    if (!mounted) return;
    if (taken) {
      setState(() => _error = 'You already have a category with that name.');
      return;
    }

    if (_isRenaming) {
      await db.renameCategory(widget.existing!.id, name);
    } else {
      await db.addCategory(name, _kind);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isRenaming ? 'Rename category' : 'New category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Choosing the type only makes sense when creating.
          if (!_isRenaming) ...[
            SegmentedButton<TxnKind>(
              segments: const [
                ButtonSegment(value: TxnKind.expense, label: Text('Expense')),
                ButtonSegment(value: TxnKind.income, label: Text('Income')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
