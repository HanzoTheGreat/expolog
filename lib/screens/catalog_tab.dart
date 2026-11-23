import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/background_timer.dart';
import '../core/format.dart';
import '../src/rust/model.dart';

class CatalogTab extends StatefulWidget {
  const CatalogTab({super.key, required this.state});

  final AppState state;

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  bool _showArchived = false;

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openCategoryDialog({Category? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String selectedHex = existing?.colorHex ?? kCategoryPalette.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Neue Kategorie' : 'Kategorie bearbeiten',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Name (z. B. Kontrolle, ÖPNV, Soziales)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Farbe für Zeitstrahl-Spur',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kCategoryPalette.map((hex) {
                        final isSelected =
                            hex.toUpperCase() == selectedHex.toUpperCase();
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedHex = hex),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: parseHexColor(hex),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2.5)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showMessage('Kategoriename darf nicht leer sein.');
      return;
    }

    try {
      await widget.state.core.upsertCategory(
        input: CategoryInput(
          id: existing?.id,
          name: name,
          colorHex: selectedHex,
          sortOrder:
              existing?.sortOrder ?? widget.state.catalogWithArchived.length,
        ),
      );
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('Fehler beim Speichern: $e');
    }
  }

  Future<void> _deleteCategory(Category cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategorie löschen?'),
        content: Text(
          'Kategorie „${cat.name}“ löschen? Dies ist nur möglich, wenn keine Themen mehr darin liegen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await widget.state.core.deleteCategory(id: cat.id);
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('$e');
    }
  }

  Future<void> _openItemDialog({
    required int categoryId,
    ExposureItem? existing,
  }) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final triggerCtrl = TextEditingController(
      text: existing?.triggerDesc ?? '',
    );
    final fearCtrl = TextEditingController(text: existing?.coreFear ?? '');
    final responseCtrl = TextEditingController(
      text: existing?.typicalResponse ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null ? 'Neues Thema / Auslöser' : 'Thema bearbeiten',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Konkretes Thema (z. B. Herd prüfen, U-Bahn)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: triggerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Typischer Auslöser / Situation (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fearCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kernbefürchtung (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: responseCtrl,
                decoration: const InputDecoration(
                  labelText:
                      'Typische Reaktion / Vermeidung / Ritual (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      _showMessage('Titel darf nicht leer sein.');
      return;
    }

    try {
      await widget.state.core.upsertExposureItem(
        input: ExposureItemInput(
          id: existing?.id,
          categoryId: categoryId,
          title: title,
          triggerDesc: triggerCtrl.text.trim(),
          coreFear: fearCtrl.text.trim(),
          typicalResponse: responseCtrl.text.trim(),
        ),
      );
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('Fehler beim Speichern: $e');
    }
  }

  Future<void> _openSafetyBehaviorDialog({
    required int exposureItemId,
    SafetyBehavior? existing,
  }) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null
              ? 'Sicherheitsverhalten / Ersatzhandlung'
              : 'Eintrag bearbeiten',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText:
                      'Bezeichnung (z. B. Foto machen, am Ausgang stehen)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) {
      _showMessage('Bezeichnung darf nicht leer sein.');
      return;
    }

    try {
      await widget.state.core.upsertSafetyBehavior(
        input: SafetyBehaviorInput(
          id: existing?.id,
          exposureItemId: exposureItemId,
          label: label,
          notes: notesCtrl.text.trim(),
        ),
      );
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('Fehler beim Speichern: $e');
    }
  }

  Future<void> _toggleArchiveItem(ExposureItem item) async {
    try {
      await widget.state.core.setExposureItemArchived(
        id: item.id,
        archived: !item.archived,
      );
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('Fehler: $e');
    }
  }

  Future<void> _deleteItem(ExposureItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thema dauerhaft löschen?'),
        content: Text(
          '„${item.title}“ inkl. aller Sicherheitsverhalten, Zeitstrahl-Phasen und Expositions-Protokolle wird gelöscht. Alternativ kannst du es archivieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await widget.state.core.deleteExposureItem(id: item.id);
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('Fehler: $e');
    }
  }

  Future<void> _toggleArchiveSafetyBehavior(SafetyBehavior sb) async {
    try {
      await widget.state.core.setSafetyBehaviorArchived(
        id: sb.id,
        archived: !sb.archived,
      );
      await widget.state.refreshCatalog();
    } catch (e) {
      _showMessage('Fehler: $e');
    }
  }

  Future<void> _openSettingsSheet() async {
    bool ignoringBattery =
        await BackgroundTimerBridge.isIgnoringBatteryOptimizations();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return ListenableBuilder(
              listenable: widget.state,
              builder: (ctx, _) {
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Standardwerte für Expositionen',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Anspannungs-Skala',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 10, label: Text('0 – 10')),
                            ButtonSegment(value: 100, label: Text('0 – 100')),
                          ],
                          selected: {widget.state.defaultScaleMax},
                          onSelectionChanged: (set) {
                            widget.state.setDefaultScaleMax(set.first);
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Check-in-Intervall',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 180, label: Text('3 min')),
                            ButtonSegment(value: 300, label: Text('5 min')),
                            ButtonSegment(value: 600, label: Text('10 min')),
                          ],
                          selected: {widget.state.defaultIntervalSecs},
                          onSelectionChanged: (set) {
                            widget.state.setDefaultIntervalSecs(set.first);
                          },
                        ),
                        if (BackgroundTimerBridge.isSupported) ...[
                          const Divider(height: 28),
                          Text(
                            'Hintergrund-Vibration (Android)',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ignoringBattery
                                ? 'Akku-Optimierung ist deaktiviert – Hintergrund-Timer laufen ohne System-Drosselung.'
                                : 'Akku-Optimierung ist noch aktiv. Für zuverlässige Pings bei gesperrtem Display in den App-Einstellungen auf „Keine Beschränkungen“ stellen.',
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurface
                                  .withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: BackgroundTimerBridge.testVibrate,
                                  icon: const Icon(Icons.vibration, size: 18),
                                  label: const Text('Test-Ping'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await BackgroundTimerBridge.openAppSettings();
                                    final next =
                                        await BackgroundTimerBridge.isIgnoringBatteryOptimizations();
                                    setSheetState(() => ignoringBattery = next);
                                  },
                                  icon: const Icon(
                                    Icons.battery_saver_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('App-Einstell.'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final groups = _showArchived
            ? widget.state.catalogWithArchived
            : widget.state.catalog;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Katalog & System'),
            actions: [
              IconButton(
                tooltip: _showArchived
                    ? 'Archivierte ausblenden'
                    : 'Archivierte anzeigen',
                onPressed: () => setState(() => _showArchived = !_showArchived),
                icon: Icon(
                  _showArchived
                      ? Icons.inventory_2
                      : Icons.inventory_2_outlined,
                ),
              ),
              IconButton(
                tooltip: 'Standardwerte & Vibration',
                onPressed: _openSettingsSheet,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'App sperren',
                onPressed: widget.state.lock,
                icon: const Icon(Icons.lock_outline),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openCategoryDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Kategorie'),
          ),
          body: groups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Noch keine Kategorien angelegt.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lege in einer ruhigen Phase zuerst eine Kategorie (z. B. Kontrolle, ÖPNV, Soziales) und darunter deine konkreten Themen samt Sicherheitsverhalten an.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final cat = group.category;
                    final color = parseHexColor(cat.colorHex);

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    cat.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Thema hinzufügen',
                                  onPressed: () =>
                                      _openItemDialog(categoryId: cat.id),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openCategoryDialog(existing: cat);
                                    } else if (value == 'delete') {
                                      _deleteCategory(cat);
                                    }
                                  },
                                  itemBuilder: (ctx) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Kategorie bearbeiten'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Kategorie löschen'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (group.items.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Keine Themen in dieser Kategorie.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                              )
                            else ...[
                              const Divider(height: 16),
                              ...group.items.map(
                                (item) => _ExposureItemTile(
                                  item: item,
                                  onEdit: () => _openItemDialog(
                                    categoryId: cat.id,
                                    existing: item,
                                  ),
                                  onToggleArchive: () =>
                                      _toggleArchiveItem(item),
                                  onDelete: () => _deleteItem(item),
                                  onAddSafetyBehavior: () =>
                                      _openSafetyBehaviorDialog(
                                        exposureItemId: item.id,
                                      ),
                                  onEditSafetyBehavior: (sb) =>
                                      _openSafetyBehaviorDialog(
                                        exposureItemId: item.id,
                                        existing: sb,
                                      ),
                                  onToggleArchiveSafetyBehavior:
                                      _toggleArchiveSafetyBehavior,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _ExposureItemTile extends StatelessWidget {
  const _ExposureItemTile({
    required this.item,
    required this.onEdit,
    required this.onToggleArchive,
    required this.onDelete,
    required this.onAddSafetyBehavior,
    required this.onEditSafetyBehavior,
    required this.onToggleArchiveSafetyBehavior,
  });

  final ExposureItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;
  final VoidCallback onAddSafetyBehavior;
  final ValueChanged<SafetyBehavior> onEditSafetyBehavior;
  final ValueChanged<SafetyBehavior> onToggleArchiveSafetyBehavior;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.68);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  decoration: item.archived
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                        if (item.archived) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(archiviert)',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: muted),
                          ),
                        ],
                      ],
                    ),
                    if (item.typicalResponse.isNotEmpty)
                      Text(
                        'Typische Reaktion: ${item.typicalResponse}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: muted),
                      ),
                    if (item.coreFear.isNotEmpty)
                      Text(
                        'Befürchtung: ${item.coreFear}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'sb') onAddSafetyBehavior();
                  if (value == 'archive') onToggleArchive();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  const PopupMenuItem(
                    value: 'sb',
                    child: Text('Sicherheitsverhalten hinzufügen'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(item.archived ? 'Reaktivieren' : 'Archivieren'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...item.safetyBehaviors.map(
                (sb) => InputChip(
                  label: Text(
                    sb.archived ? '${sb.label} (archiviert)' : sb.label,
                  ),
                  onPressed: () => onEditSafetyBehavior(sb),
                  onDeleted: () => onToggleArchiveSafetyBehavior(sb),
                  deleteIcon: Icon(
                    sb.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 16,
                  ),
                  deleteButtonTooltipMessage: sb.archived
                      ? 'Reaktivieren'
                      : 'Archivieren',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Sicherheitsverhalten'),
                onPressed: onAddSafetyBehavior,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
