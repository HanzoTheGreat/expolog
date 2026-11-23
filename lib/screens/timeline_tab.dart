import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../src/rust/model.dart';
import '../widgets/timeline_canvas.dart';
import 'timeline_sheets.dart';

class TimelineTab extends StatelessWidget {
  const TimelineTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return _TimelineBody(state: state, presentationLocked: false);
  }
}

/// Eigenständige, gesperrte Vollbild-Ansicht für Gespräche / Erstgespräche
class TimelinePresentationScreen extends StatelessWidget {
  const TimelinePresentationScreen({
    super.key,
    required this.state,
    required this.initialStartDay,
    required this.initialSpanDays,
    required this.initialExpandedIds,
  });

  final AppState state;
  final double initialStartDay;
  final double initialSpanDays;
  final Set<int> initialExpandedIds;

  @override
  Widget build(BuildContext context) {
    return _TimelineBody(
      state: state,
      presentationLocked: true,
      initialStartDay: initialStartDay,
      initialSpanDays: initialSpanDays,
      initialExpandedIds: initialExpandedIds,
    );
  }
}

class _TimelineBody extends StatefulWidget {
  const _TimelineBody({
    required this.state,
    required this.presentationLocked,
    this.initialStartDay,
    this.initialSpanDays,
    this.initialExpandedIds,
  });

  final AppState state;
  final bool presentationLocked;
  final double? initialStartDay;
  final double? initialSpanDays;
  final Set<int>? initialExpandedIds;

  @override
  State<_TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends State<_TimelineBody> {
  late double _startDay;
  late double _spanDays;
  late final Set<int> _expandedCategoryIds;

  TimelineViewportData? _viewportData;
  int? _fetchedFromDay;
  int? _fetchedToDay;
  bool _fetchedMarkers = false;
  bool _includeArchived = false;
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final today = todayEpochDay();
    _spanDays = widget.initialSpanDays ?? 365.0;
    _startDay = widget.initialStartDay ?? (today - _spanDays + 20.0);
    _expandedCategoryIds = {...?widget.initialExpandedIds};

    widget.state.addListener(_onAppStateChanged);
    _fetchViewport(force: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.state.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!widget.state.isUnlocked) return;
    _fetchViewport(force: true);
  }

  bool get _shouldShowSessionMarkers => _spanDays <= 180.0;

  Future<void> _fetchViewport({bool force = false}) async {
    if (!widget.state.isUnlocked) return;

    final visFrom = _startDay.floor();
    final visTo = (_startDay + _spanDays).ceil();
    final wantMarkers = _shouldShowSessionMarkers;

    final needsFetch =
        force ||
        _viewportData == null ||
        _fetchedFromDay == null ||
        _fetchedToDay == null ||
        visFrom < _fetchedFromDay! ||
        visTo > _fetchedToDay! ||
        (wantMarkers != _fetchedMarkers);

    if (!needsFetch) return;

    // Puffer links & rechts, damit Panning flüssig bleibt
    final pad = (_spanDays * 0.75).ceil().clamp(60, 1200);
    final queryFrom = visFrom - pad;
    final queryTo = visTo + pad;

    try {
      final data = await widget.state.core.getTimelineViewport(
        fromDay: queryFrom,
        toDay: queryTo,
        includeSessionMarkers: wantMarkers,
        includeArchived: _includeArchived,
      );
      if (!mounted) return;
      setState(() {
        _viewportData = data;
        _fetchedFromDay = queryFrom;
        _fetchedToDay = queryTo;
        _fetchedMarkers = wantMarkers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onViewportChanged(double nextStart, double nextSpan) {
    setState(() {
      _startDay = nextStart;
      _spanDays = nextSpan;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      _fetchViewport();
    });
  }

  void _applyPresetSpan(double days) {
    final today = todayEpochDay();
    final margin = (days * 0.06).clamp(3.0, 45.0);
    setState(() {
      _spanDays = days;
      _startDay = today - days + margin;
    });
    _fetchViewport(force: true);
  }

  void _jumpToToday() {
    final today = todayEpochDay();
    final margin = (_spanDays * 0.08).clamp(3.0, 45.0);
    setState(() {
      _startDay = today - _spanDays + margin;
    });
    _fetchViewport();
  }

  void _toggleCategory(int categoryId) {
    setState(() {
      if (_expandedCategoryIds.contains(categoryId)) {
        _expandedCategoryIds.remove(categoryId);
      } else {
        _expandedCategoryIds.add(categoryId);
      }
    });
  }

  Future<void> _openTransitionSheet({int? itemId}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          TransitionPhaseSheet(state: widget.state, initialItemId: itemId),
    );
    if (saved == true) {
      await _fetchViewport(force: true);
    }
  }

  Future<void> _openContextSheet({ContextEvent? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContextEventSheet(
        state: widget.state,
        existing: existing,
        readOnly: widget.presentationLocked,
      ),
    );
    if (saved == true) {
      await _fetchViewport(force: true);
    }
  }

  Future<void> _openItemSheet(int exposureItemId) async {
    final item = widget.state.findItemById(exposureItemId);
    if (item == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ItemPhasesSheet(
        state: widget.state,
        item: item,
        readOnly: widget.presentationLocked,
      ),
    );
    if (changed == true) {
      await _fetchViewport(force: true);
    }
  }

  Future<void> _openPhaseTap(int exposureItemId, TimelinePhase phase) async {
    final item = widget.state.findItemById(exposureItemId);
    if (item == null) return;

    if (widget.presentationLocked) {
      await _openItemSheet(exposureItemId);
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          PhaseEditorSheet(state: widget.state, item: item, existing: phase),
    );
    if (saved == true) {
      await _fetchViewport(force: true);
    }
  }

  void _enterPresentationMode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimelinePresentationScreen(
          state: widget.state,
          initialStartDay: _startDay,
          initialSpanDays: _spanDays,
          initialExpandedIds: _expandedCategoryIds,
        ),
      ),
    );
  }

  Future<void> _unlockPresentationMode() async {
    final passCtrl = TextEditingController();
    String? dialogError;

    final unlocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Vorzeige-Modus entsperren'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Passphrase / PIN',
                ),
                onSubmitted: (_) {
                  if (widget.state.verifyPassphrase(passCtrl.text)) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(
                      () => dialogError = 'Passphrase nicht korrekt.',
                    );
                  }
                },
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                if (widget.state.verifyPassphrase(passCtrl.text)) {
                  Navigator.pop(ctx, true);
                } else {
                  setDialogState(
                    () => dialogError = 'Passphrase nicht korrekt.',
                  );
                }
              },
              child: const Text('Entsperren'),
            ),
          ],
        ),
      ),
    );

    passCtrl.dispose();
    if (unlocked == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = _viewportData;
    final hasAnyGroups = data != null && data.groups.isNotEmpty;

    return PopScope(
      canPop: !widget.presentationLocked,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            widget.presentationLocked
                ? 'Verlauf (Vorzeige-Modus)'
                : 'Zeitstrahl',
          ),
          actions: widget.presentationLocked
              ? [
                  TextButton.icon(
                    onPressed: _unlockPresentationMode,
                    icon: const Icon(Icons.lock_open_outlined, size: 18),
                    label: const Text('Entsperren'),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: _includeArchived
                        ? 'Archivierte ausblenden'
                        : 'Archivierte anzeigen',
                    onPressed: () {
                      setState(() => _includeArchived = !_includeArchived);
                      _fetchViewport(force: true);
                    },
                    icon: Icon(
                      _includeArchived
                          ? Icons.inventory_2
                          : Icons.inventory_2_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kontext-Ereignis hinzufügen',
                    onPressed: () => _openContextSheet(),
                    icon: const Icon(Icons.flag_outlined),
                  ),
                  IconButton(
                    tooltip: 'Vorzeige-Modus (Navigation sperren)',
                    onPressed: _enterPresentationMode,
                    icon: const Icon(Icons.screen_lock_portrait_outlined),
                  ),
                  IconButton(
                    tooltip: 'App sperren',
                    onPressed: widget.state.lock,
                    icon: const Icon(Icons.lock_outline),
                  ),
                ],
        ),
        floatingActionButton: widget.presentationLocked
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openTransitionSheet(),
                icon: const Icon(Icons.update),
                label: const Text('Status ändern'),
              ),
        body: Column(
          children: [
            // Kompakte Zoom- & Navigationsleiste
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  _ZoomChip(
                    label: '3M',
                    selected: _spanDays <= 105,
                    onTap: () => _applyPresetSpan(90),
                  ),
                  const SizedBox(width: 6),
                  _ZoomChip(
                    label: '1J',
                    selected: _spanDays > 105 && _spanDays <= 540,
                    onTap: () => _applyPresetSpan(365),
                  ),
                  const SizedBox(width: 6),
                  _ZoomChip(
                    label: '3J',
                    selected: _spanDays > 540 && _spanDays <= 1460,
                    onTap: () => _applyPresetSpan(1095),
                  ),
                  const SizedBox(width: 6),
                  _ZoomChip(
                    label: '5J',
                    selected: _spanDays > 1460,
                    onTap: () => _applyPresetSpan(1825),
                  ),
                  const SizedBox(width: 10),
                  ActionChip(
                    avatar: const Icon(Icons.today, size: 16),
                    label: const Text('Heute'),
                    onPressed: _jumpToToday,
                  ),
                ],
              ),
            ),
            if (widget.presentationLocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                color: scheme.primary.withValues(alpha: 0.14),
                child: Text(
                  'Vorzeige-Modus aktiv · Antippen zeigt Details, Bearbeiten und Navigation sind gesperrt.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.primary),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : !hasAnyGroups
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Lege im Tab „Katalog“ Kategorien und Themen an. Über „Status ändern“ oder das Fahnen-Symbol oben trägst du anschließend Verlaufsphasen und Kontext-Ereignisse ein.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.72),
                              ),
                        ),
                      ),
                    )
                  : TimelineCanvas(
                      viewportData: data,
                      startDay: _startDay,
                      spanDays: _spanDays,
                      todayDay: todayEpochDay(),
                      expandedCategoryIds: _expandedCategoryIds,
                      onViewportChanged: _onViewportChanged,
                      onToggleCategory: _toggleCategory,
                      onTapItem: _openItemSheet,
                      onTapPhase: _openPhaseTap,
                      onTapContextEvent: (ev) =>
                          _openContextSheet(existing: ev),
                    ),
            ),
            // Dezente Legende am unteren Rand
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outline.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Text(
                'Kategorie antippen = auf-/zuklappen · Balkendicke = Belastung · S-Badge = Sicherheitsverhalten · Punkte (≤6M) = Expositionen',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: scheme.onSurface.withValues(alpha: 0.62),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}
