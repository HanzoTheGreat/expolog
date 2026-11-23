import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/background_timer.dart';
import '../core/format.dart';
import '../src/rust/model.dart';
import 'exposure_setup_sheet.dart';
import 'item_curves_screen.dart';

class ExposureTab extends StatefulWidget {
  const ExposureTab({super.key, required this.state});

  final AppState state;

  @override
  State<ExposureTab> createState() => _ExposureTabState();
}

class _ExposureTabState extends State<ExposureTab> {
  Timer? _urgeTicker;
  int _nowSecs = nowUnixSecs();
  bool _notifiedUrgeDone = false;
  bool _urgeBusy = false;

  @override
  void initState() {
    super.initState();
    _urgeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final active = widget.state.activeUrgeDelay;
      if (active == null) {
        _notifiedUrgeDone = false;
        return;
      }
      final now = nowUnixSecs();
      final remaining = active.targetDurationSecs - (now - active.startedAt);
      if (remaining <= 0 && !_notifiedUrgeDone) {
        _notifiedUrgeDone = true;
        // Auf Android übernimmt der Foreground-Service den haptischen Puls
        if (!BackgroundTimerBridge.isSupported) {
          HapticFeedback.mediumImpact();
        }
      }
      if (mounted) {
        setState(() => _nowSecs = now);
      }
    });
  }

  @override
  void dispose() {
    _urgeTicker?.cancel();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _startUrgeDelay(int durationSecs) async {
    if (_urgeBusy) return;
    setState(() => _urgeBusy = true);
    try {
      await BackgroundTimerBridge.requestNotificationPermission();
      await widget.state.core.startUrgeDelay(
        exposureItemId: null,
        targetDurationSecs: durationSecs,
      );
      _nowSecs = nowUnixSecs();
      _notifiedUrgeDone = false;
      await widget.state.refreshAll();
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _urgeBusy = false);
    }
  }

  Future<void> _finishUrgeDelay(UrgeDelay active, UrgeOutcome outcome) async {
    if (_urgeBusy) return;
    setState(() => _urgeBusy = true);
    try {
      await widget.state.core.finishUrgeDelay(id: active.id, outcome: outcome);
      if (outcome == UrgeOutcome.extended) {
        await widget.state.core.startUrgeDelay(
          exposureItemId: active.exposureItemId,
          targetDurationSecs: 600,
        );
        _nowSecs = nowUnixSecs();
        _notifiedUrgeDone = false;
      }
      await widget.state.refreshAll();
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _urgeBusy = false);
    }
  }

  Future<void> _openSetup(ExposureItem item) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ExposureSetupSheet(state: widget.state, item: item),
    );
  }

  void _openCurves(ExposureItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemCurvesScreen(state: widget.state, item: item),
      ),
    );
  }

  Widget _buildUrgeCard(BuildContext context, UrgeDelay? active) {
    final scheme = Theme.of(context).colorScheme;

    if (active == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spontaner Aufschub-Timer',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Für akute Kontroll-, Rückversicherungs- oder Vermeidungsimpulse – 1 Tap, ohne Ausfüllen.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.68)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _urgeBusy ? null : () => _startUrgeDelay(300),
                      child: const Text('5 min'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _urgeBusy ? null : () => _startUrgeDelay(600),
                      child: const Text('10 min'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _urgeBusy ? null : () => _startUrgeDelay(900),
                      child: const Text('15 min'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final elapsed = max(0, _nowSecs - active.startedAt);
    final remaining = active.targetDurationSecs - elapsed;
    final done = remaining <= 0;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: done ? scheme.secondary : scheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  done ? 'Aufschub abgelaufen' : 'Aufschub läuft',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: done ? scheme.secondary : scheme.primary,
                  ),
                ),
                Text(
                  done ? '00:00' : formatDurationMmSs(remaining),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _urgeBusy
                      ? null
                      : () => _finishUrgeDelay(active, UrgeOutcome.subsided),
                  child: const Text('Abgeklungen'),
                ),
                OutlinedButton(
                  onPressed: _urgeBusy
                      ? null
                      : () => _finishUrgeDelay(active, UrgeOutcome.extended),
                  child: const Text('+10 min'),
                ),
                OutlinedButton(
                  onPressed: _urgeBusy
                      ? null
                      : () => _finishUrgeDelay(active, UrgeOutcome.performed),
                  child: const Text('Ausgeführt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final groups = widget.state.catalog;
        final hasItems = groups.any((g) => g.items.isNotEmpty);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Exposition'),
            actions: [
              IconButton(
                tooltip: 'App sperren',
                onPressed: widget.state.lock,
                icon: const Icon(Icons.lock_outline),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _buildUrgeCard(context, widget.state.activeUrgeDelay),
              const SizedBox(height: 10),
              if (!hasItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Lege im Tab „Katalog“ deine Kategorien und konkreten Auslöser bzw. Themen an – sie erscheinen dann direkt hier für den 1-Tap-Start.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.72),
                    ),
                  ),
                )
              else
                ...groups.where((g) => g.items.isNotEmpty).map((group) {
                  final color = parseHexColor(group.category.colorHex);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              group.category.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                      ...group.items.map(
                        (item) => Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              16,
                              6,
                              8,
                              6,
                            ),
                            title: Text(item.title),
                            subtitle: item.triggerDesc.isNotEmpty
                                ? Text(item.triggerDesc)
                                : null,
                            onTap: () => _openCurves(item),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Verlaufskurven anzeigen',
                                  onPressed: () => _openCurves(item),
                                  icon: const Icon(Icons.show_chart),
                                ),
                                IconButton.filledTonal(
                                  tooltip: 'Exposition starten',
                                  onPressed: () => _openSetup(item),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
