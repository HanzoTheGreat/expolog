import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;

import '../core/app_state.dart';
import '../core/format.dart';
import '../src/rust/model.dart';

/// Kompakter Picker für unscharfe Daten (Tag / Monat / Quartal / Jahr)
class FuzzyDateInput extends StatelessWidget {
  const FuzzyDateInput({
    super.key,
    required this.label,
    required this.value,
    required this.isEnd,
    required this.onChanged,
  });

  final String label;
  final FuzzyDate value;
  final bool isEnd;
  final ValueChanged<FuzzyDate> onChanged;

  Future<void> _pickExactDay(BuildContext context) async {
    final current = epochDayToDateTime(value.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    onChanged(
      FuzzyDate(day: dateTimeToEpochDay(picked), precision: DatePrecision.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dt = epochDayToDateTime(value.day);
    final currentYear = DateTime.now().year;
    final years = List.generate(
      currentYear - 1995 + 2,
      (i) => currentYear + 1 - i,
    );
    final quarter = ((dt.month - 1) ~/ 3) + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<DatePrecision>(
          showSelectedIcon: false,
          segments: DatePrecision.values
              .map(
                (p) =>
                    ButtonSegment(value: p, label: Text(datePrecisionLabel(p))),
              )
              .toList(),
          selected: {value.precision},
          onSelectionChanged: (set) {
            final p = set.first;
            onChanged(
              buildFuzzyDate(
                precision: p,
                year: dt.year,
                month: dt.month,
                day: dt.day,
                quarter: quarter,
                isEnd: isEnd,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        if (value.precision == DatePrecision.day)
          OutlinedButton.icon(
            onPressed: () => _pickExactDay(context),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(formatEpochDay(value.day)),
          )
        else
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Jahr',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: years.contains(dt.year) ? dt.year : currentYear,
                      items: years
                          .map(
                            (y) =>
                                DropdownMenuItem(value: y, child: Text('$y')),
                          )
                          .toList(),
                      onChanged: (y) {
                        if (y == null) return;
                        onChanged(
                          buildFuzzyDate(
                            precision: value.precision,
                            year: y,
                            month: dt.month,
                            quarter: quarter,
                            isEnd: isEnd,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (value.precision == DatePrecision.month) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Monat',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: dt.month,
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text((i + 1).toString().padLeft(2, '0')),
                          ),
                        ),
                        onChanged: (m) {
                          if (m == null) return;
                          onChanged(
                            buildFuzzyDate(
                              precision: DatePrecision.month,
                              year: dt.year,
                              month: m,
                              isEnd: isEnd,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
              if (value.precision == DatePrecision.quarter) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Quartal',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: quarter,
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Q1 (Jan–Mär)'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('Q2 (Apr–Jun)'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('Q3 (Jul–Sep)'),
                          ),
                          DropdownMenuItem(
                            value: 4,
                            child: Text('Q4 (Okt–Dez)'),
                          ),
                        ],
                        onChanged: (q) {
                          if (q == null) return;
                          onChanged(
                            buildFuzzyDate(
                              precision: DatePrecision.quarter,
                              year: dt.year,
                              quarter: q,
                              isEnd: isEnd,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Schneller Statuswechsel im Alltag („Ab Datum X: neuer Status“)
class TransitionPhaseSheet extends StatefulWidget {
  const TransitionPhaseSheet({
    super.key,
    required this.state,
    this.initialItemId,
  });

  final AppState state;
  final int? initialItemId;

  @override
  State<TransitionPhaseSheet> createState() => _TransitionPhaseSheetState();
}

class _TransitionPhaseSheetState extends State<TransitionPhaseSheet> {
  int? _selectedItemId;
  late int _effectiveDay;
  Severity _severity = Severity.moderate;
  final Set<int> _selectedSafetyIds = {};
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _effectiveDay = todayEpochDay();
    _selectedItemId = widget.initialItemId ?? _firstAvailableItemId();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  int? _firstAvailableItemId() {
    for (final g in widget.state.catalog) {
      if (g.items.isNotEmpty) return g.items.first.id;
    }
    return null;
  }

  List<ExposureItem> _allActiveItems() {
    return [for (final g in widget.state.catalog) ...g.items];
  }

  Future<void> _pickDay() async {
    final dt = epochDayToDateTime(_effectiveDay);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(dt.year, dt.month, dt.day),
      firstDate: DateTime(1995),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _effectiveDay = dateTimeToEpochDay(picked));
    }
  }

  Future<void> _save() async {
    final itemId = _selectedItemId;
    if (itemId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.state.core.transitionItemPhase(
        input: TransitionPhaseInput(
          exposureItemId: itemId,
          effectiveDay: _effectiveDay,
          severity: _severity,
          activeSafetyBehaviorIds: Int64List.fromList(
            _selectedSafetyIds.toList()..sort(),
          ),
          notes: _notesCtrl.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final items = _allActiveItems();
    final selectedItem = _selectedItemId != null
        ? widget.state.findItemById(_selectedItemId!)
        : null;
    final activeSafety = (selectedItem?.safetyBehaviors ?? const [])
        .where((sb) => !sb.archived)
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Status ab Datum ändern',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Beendet eine eventuell laufende Phase automatisch zum Vortag und startet die neue Phase.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Text('Lege zuerst im Katalog mindestens ein Thema an.')
            else ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Thema',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedItemId,
                    items: items
                        .map(
                          (it) => DropdownMenuItem(
                            value: it.id,
                            child: Text(it.title),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      setState(() {
                        _selectedItemId = id;
                        _selectedSafetyIds.clear();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Gültig ab',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(formatEpochDay(_effectiveDay)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Belastungsgrad',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Severity.values.map((s) {
                  return ChoiceChip(
                    label: Text(severityLabel(s)),
                    selected: _severity == s,
                    onSelected: (_) => setState(() => _severity = s),
                  );
                }).toList(),
              ),
              if (activeSafety.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Aktives Sicherheitsverhalten / Ersatzhandlungen',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: activeSafety.map((sb) {
                    final selected = _selectedSafetyIds.contains(sb.id);
                    return FilterChip(
                      label: Text(sb.label),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedSafetyIds.add(sb.id);
                          } else {
                            _selectedSafetyIds.remove(sb.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notiz zur Phase (optional)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Status speichern'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vollständiger Phasen-Editor (auch für rückwirkende, unscharfe Zeiträume)
class PhaseEditorSheet extends StatefulWidget {
  const PhaseEditorSheet({
    super.key,
    required this.state,
    required this.item,
    this.existing,
  });

  final AppState state;
  final ExposureItem item;
  final TimelinePhase? existing;

  @override
  State<PhaseEditorSheet> createState() => _PhaseEditorSheetState();
}

class _PhaseEditorSheetState extends State<PhaseEditorSheet> {
  late FuzzyDate _start;
  late bool _ongoing;
  late FuzzyDate _end;
  late Severity _severity;
  late final Set<int> _selectedSafetyIds;
  late final TextEditingController _notesCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    final today = todayEpochDay();
    _start =
        ex?.start ?? FuzzyDate(day: today - 90, precision: DatePrecision.month);
    _ongoing = ex == null ? false : ex.end == null;
    _end = ex?.end ?? FuzzyDate(day: today, precision: DatePrecision.month);
    _severity = ex?.severity ?? Severity.moderate;
    _selectedSafetyIds = ex != null
        ? ex.activeSafetyBehaviorIds.map((e) => e.toInt()).toSet()
        : <int>{};
    _notesCtrl = TextEditingController(text: ex?.notes ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.state.core.upsertTimelinePhase(
        input: TimelinePhaseInput(
          id: widget.existing?.id,
          exposureItemId: widget.item.id,
          start: _start,
          end: _ongoing ? null : _end,
          severity: _severity,
          activeSafetyBehaviorIds: Int64List.fromList(
            _selectedSafetyIds.toList()..sort(),
          ),
          notes: _notesCtrl.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final ex = widget.existing;
    if (ex == null) return;
    setState(() => _saving = true);
    try {
      await widget.state.core.deleteTimelinePhase(id: ex.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safetyBehaviors = widget.item.safetyBehaviors;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing == null
                        ? 'Phase hinzufügen · ${widget.item.title}'
                        : 'Phase bearbeiten · ${widget.item.title}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.existing != null)
                  IconButton(
                    tooltip: 'Phase löschen',
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FuzzyDateInput(
              label: 'Beginn',
              value: _start,
              isEnd: false,
              onChanged: (v) => setState(() => _start = v),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Läuft bis heute (offenes Ende)'),
              value: _ongoing,
              onChanged: (v) => setState(() => _ongoing = v),
            ),
            if (!_ongoing) ...[
              const SizedBox(height: 8),
              FuzzyDateInput(
                label: 'Ende',
                value: _end,
                isEnd: true,
                onChanged: (v) => setState(() => _end = v),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Belastungsgrad',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Severity.values.map((s) {
                return ChoiceChip(
                  label: Text(severityLabel(s)),
                  selected: _severity == s,
                  onSelected: (_) => setState(() => _severity = s),
                );
              }).toList(),
            ),
            if (safetyBehaviors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Sicherheitsverhalten / Ersatzhandlungen in dieser Phase',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: safetyBehaviors.map((sb) {
                  final selected = _selectedSafetyIds.contains(sb.id);
                  return FilterChip(
                    label: Text(sb.label),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedSafetyIds.add(sb.id);
                        } else {
                          _selectedSafetyIds.remove(sb.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notiz (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Übersicht aller Phasen eines Themas (auch im schreibgeschützten Vorzeige-Modus nutzbar)
class ItemPhasesSheet extends StatefulWidget {
  const ItemPhasesSheet({
    super.key,
    required this.state,
    required this.item,
    required this.readOnly,
  });

  final AppState state;
  final ExposureItem item;
  final bool readOnly;

  @override
  State<ItemPhasesSheet> createState() => _ItemPhasesSheetState();
}

class _ItemPhasesSheetState extends State<ItemPhasesSheet> {
  List<TimelinePhase> _phases = const [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await widget.state.core.listPhasesForItem(
      exposureItemId: widget.item.id,
    );
    if (!mounted) return;
    setState(() {
      _phases = list.reversed.toList();
      _loading = false;
    });
  }

  String _safetyLabel(int id) {
    for (final sb in widget.item.safetyBehaviors) {
      if (sb.id == id) return sb.label;
    }
    return 'Sicherheitsverhalten #$id';
  }

  Future<void> _openEditPhase({TimelinePhase? phase}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PhaseEditorSheet(
        state: widget.state,
        item: widget.item,
        existing: phase,
      ),
    );
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _openTransition() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TransitionPhaseSheet(
        state: widget.state,
        initialItemId: widget.item.id,
      ),
    );
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_changed);
        }
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollCtrl) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.item.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (widget.item.typicalResponse.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Typische Reaktion: ${widget.item.typicalResponse}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!widget.readOnly) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _openTransition,
                          icon: const Icon(Icons.update, size: 18),
                          label: const Text('Status ändern'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openEditPhase(),
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('Histor. Phase'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _phases.isEmpty
                      ? const Center(
                          child: Text('Noch keine Verlaufsphasen eingetragen.'),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: _phases.length,
                          itemBuilder: (ctx, i) {
                            final p = _phases[i];
                            final range = p.end == null
                                ? '${formatFuzzyDate(p.start)} – heute'
                                : '${formatFuzzyDate(p.start)} – ${formatFuzzyDate(p.end!)}';
                            return Card(
                              child: ListTile(
                                title: Text(
                                  '${severityLabel(p.severity)} · $range',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (p.activeSafetyBehaviorIds.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: p.activeSafetyBehaviorIds
                                              .map(
                                                (id) => Chip(
                                                  label: Text(
                                                    _safetyLabel(id.toInt()),
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                    if (p.notes.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(p.notes),
                                      ),
                                  ],
                                ),
                                trailing: widget.readOnly
                                    ? null
                                    : const Icon(Icons.edit_outlined, size: 18),
                                onTap: widget.readOnly
                                    ? null
                                    : () => _openEditPhase(phase: p),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Editor bzw. Lese-Ansicht für Kontext-Ereignisse (Klinik, Medikation, Therapie, Leben)
class ContextEventSheet extends StatefulWidget {
  const ContextEventSheet({
    super.key,
    required this.state,
    this.existing,
    this.readOnly = false,
  });

  final AppState state;
  final ContextEvent? existing;
  final bool readOnly;

  @override
  State<ContextEventSheet> createState() => _ContextEventSheetState();
}

enum _ContextDurationMode { punctual, range, ongoing }

class _ContextEventSheetState extends State<ContextEventSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  late ContextEventType _type;
  late FuzzyDate _start;
  late FuzzyDate _end;
  late _ContextDurationMode _mode;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    final today = todayEpochDay();
    _titleCtrl = TextEditingController(text: ex?.title ?? '');
    _notesCtrl = TextEditingController(text: ex?.notes ?? '');
    _type = ex?.eventType ?? ContextEventType.clinic;
    _start = ex?.start ?? FuzzyDate(day: today, precision: DatePrecision.day);
    _end = ex?.end ?? FuzzyDate(day: today, precision: DatePrecision.day);
    if (ex == null) {
      _mode = _ContextDurationMode.ongoing;
    } else if (ex.isOngoing) {
      _mode = _ContextDurationMode.ongoing;
    } else if (ex.end != null) {
      _mode = _ContextDurationMode.range;
    } else {
      _mode = _ContextDurationMode.punctual;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Bitte einen Titel eingeben.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.state.core.upsertContextEvent(
        input: ContextEventInput(
          id: widget.existing?.id,
          title: title,
          eventType: _type,
          start: _start,
          end: _mode == _ContextDurationMode.range ? _end : null,
          isOngoing: _mode == _ContextDurationMode.ongoing,
          notes: _notesCtrl.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final ex = widget.existing;
    if (ex == null) return;
    setState(() => _saving = true);
    try {
      await widget.state.core.deleteContextEvent(id: ex.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (widget.readOnly && widget.existing != null) {
      final ex = widget.existing!;
      final span = ex.isOngoing
          ? '${formatFuzzyDate(ex.start)} – laufend'
          : ex.end != null
          ? '${formatFuzzyDate(ex.start)} – ${formatFuzzyDate(ex.end!)}'
          : formatFuzzyDate(ex.start);

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: contextEventColor(ex.eventType),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  contextEventTypeLabel(ex.eventType),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(ex.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(span, style: Theme.of(context).textTheme.bodyMedium),
            if (ex.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(ex.notes),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing == null
                        ? 'Kontext-Ereignis hinzufügen'
                        : 'Kontext-Ereignis bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.existing != null)
                  IconButton(
                    tooltip: 'Löschen',
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Titel (z. B. Tagesklinik, Medikationswechsel)',
              ),
            ),
            const SizedBox(height: 14),
            Text('Typ', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ContextEventType.values.map((t) {
                return ChoiceChip(
                  avatar: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: contextEventColor(t),
                      shape: BoxShape.circle,
                    ),
                  ),
                  label: Text(contextEventTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SegmentedButton<_ContextDurationMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _ContextDurationMode.punctual,
                  label: Text('Punkt'),
                ),
                ButtonSegment(
                  value: _ContextDurationMode.range,
                  label: Text('Zeitraum'),
                ),
                ButtonSegment(
                  value: _ContextDurationMode.ongoing,
                  label: Text('Laufend'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 14),
            FuzzyDateInput(
              label: _mode == _ContextDurationMode.punctual
                  ? 'Datum'
                  : 'Beginn',
              value: _start,
              isEnd: false,
              onChanged: (v) => setState(() => _start = v),
            ),
            if (_mode == _ContextDurationMode.range) ...[
              const SizedBox(height: 14),
              FuzzyDateInput(
                label: 'Ende',
                value: _end,
                isEnd: true,
                onChanged: (v) => setState(() => _end = v),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notiz (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
