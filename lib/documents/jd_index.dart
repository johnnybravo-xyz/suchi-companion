import 'package:flutter/material.dart';

import '../api/api_models.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'jd_category_store.dart';

Future<JDCategory?> showJdCategorySheet(
  BuildContext context, {
  required JdCategoryStore store,
  String title = 'File under',
}) {
  return showModalBottomSheet<JDCategory>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SuchiColors.of(context).paper,
    sheetAnimationStyle: SuchiMotion.sheetStyle(context),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: JdIndex(
          store: store,
          title: title,
          onSelected: (category) => Navigator.pop(context, category),
        ),
      ),
    ),
  );
}

class JdIndex extends StatefulWidget {
  const JdIndex({
    required this.store,
    required this.onSelected,
    super.key,
    this.title = 'JD Index',
    this.selectedId,
    this.includeAll = false,
    this.onAllSelected,
    this.includeOffline = false,
    this.offlineSelected = false,
    this.onOfflineSelected,
  });

  final JdCategoryStore store;
  final ValueChanged<JDCategory> onSelected;
  final String title;
  final int? selectedId;
  final bool includeAll;
  final VoidCallback? onAllSelected;
  final bool includeOffline;
  final bool offlineSelected;
  final VoidCallback? onOfflineSelected;

  @override
  State<JdIndex> createState() => _JdIndexState();
}

class _JdIndexState extends State<JdIndex> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.store.load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final normalizedQuery = _query.text.trim().toLowerCase();
      final categories = widget.store.categories
          .where((category) {
            if (normalizedQuery.isEmpty) return true;
            return category.code.toString().contains(normalizedQuery) ||
                category.name.toLowerCase().contains(normalizedQuery) ||
                category.areaName.toLowerCase().contains(normalizedQuery);
          })
          .toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: widget.title,
                    excludeSemantics: true,
                    child: Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Code, area, or category',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _content(context, categories)),
        ],
      );
    },
  );

  Widget _content(BuildContext context, List<JDCategory> categories) {
    if (widget.store.loading && widget.store.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.store.error case final error?) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: InlineError(
          message: friendlyApiMessage(
            error,
            fallback: 'The JD Index could not be loaded.',
          ),
          requestId: error.requestId,
          onRetry: () => widget.store.load(force: true),
        ),
      );
    }
    if (categories.isEmpty) {
      return const SingleChildScrollView(
        child: EmptyState(
          title: 'No matching category',
          message: 'Try a JD code, area, or category name.',
          icon: Icons.folder_off_outlined,
        ),
      );
    }
    final grouped = <String, List<JDCategory>>{};
    for (final category in categories) {
      (grouped[category.areaName] ??= []).add(category);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
      children: [
        if (widget.includeOffline)
          ListTile(
            minTileHeight: 52,
            selected: widget.offlineSelected,
            leading: const Icon(Icons.offline_pin_outlined),
            title: const Text('Offline'),
            onTap: widget.onOfflineSelected,
          ),
        if (widget.includeAll)
          ListTile(
            minTileHeight: 52,
            selected: !widget.offlineSelected && widget.selectedId == null,
            leading: const Icon(Icons.all_inbox_outlined),
            title: const Text('All documents'),
            onTap: widget.onAllSelected,
          ),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 7),
            child: SectionLabel(entry.key),
          ),
          SuchiCard(
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var index = 0; index < entry.value.length; index++) ...[
                    ListTile(
                      minTileHeight: 52,
                      selected: widget.selectedId == entry.value[index].id,
                      leading: JdChip(code: entry.value[index].code),
                      title: Text(entry.value[index].name),
                      subtitle: entry.value[index].description.isEmpty
                          ? null
                          : Text(
                              entry.value[index].description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onSelected(entry.value[index]),
                    ),
                    if (index != entry.value.length - 1) const Divider(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
