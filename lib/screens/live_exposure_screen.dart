import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;

import '../core/app_state.dart';
import '../core/background_timer.dart';
import '../core/format.dart';
import '../src/rust/model.dart';

class LiveExposureScreen extends StatefulWidget {
  const LiveExposureScreen({
    super.key,
    required this.state,
    required this.session,
  });

  final AppState state;
  final ExposureSession session;

  @override
  State<LiveExposureScreen> createState() => _LiveExposureScreenState();
}

class _LiveExposureScreenState extends State<LiveExposureScreen> {
  Timer? _ticker;
  late int _nowSecs;
  late double _sliderSud;
  bool _saving = false;
  bool _notifiedCurrentDue = false;
  String? _statusNotice;

  @override
  void initState() {
    super.initState();
    _nowSecs = nowUnixSecs();
    _sliderSud = _initialSliderFromSession(widget.session);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void didUpdateWidget(covariant LiveExposureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _sliderSud = _initialSliderFromSession(widget.session);
      _notifiedCurrentDue = false;
      _statusNotice = null;
    } else if (oldWidget.session.datapoints.length !=
        widget.session.datapoints.length) {
      _notifiedCurrentDue = false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  double _initialSliderFromSession(ExposureSession s) {
    if (s.datapoints.isNotEmpty) {
      return s.datapoints.last.sudValue.toDouble();
    }
    return s.scaleMax == 10 ? 5 : 50;
  }

  int _lastCheckInSecs() {
    final points = widget.session.datapoints;
    for (int i = points.length - 1; i >= 0; i--) {
      if (points[i].flag == DatapointFlag.checkIn) {
        return points[i].recordedAt;
      }
    }
    return widget.session.startedAt;
  }

  void _onTick() {
    final now = nowUnixSecs();
    final sinceLastCheckIn = max(0, now - _lastCheckInSecs());
    final due = sinceLastCheckIn >= widget.session.intervalSecs;

    if (due && !_notifiedCurrentDue) {
      _notifiedCurrentDue = true;
      // Auf Android vibriert der Foreground-Service zuverlässig im Vorder- und Hintergrund
      if (!BackgroundTimerBridge.isSupported) {
        HapticFeedback.heavyImpact();
      }
    }

    if (mounted) {
      setState(() => _nowSecs = now);
    }
  }

  Future<void> _logPoint(DatapointFlag flag, String confirmationText) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _statusNotice = null;
    });

    try {
      await widget.state.core.addExposureDatapoint(
        input: AddExposureDatapointInput(
          sessionId: widget.session.id,
          sudValue: _sliderSud.round(),
          flag: flag,
        ),
      );
      await widget.state.refreshAll();
      if (mounted) {
        setState(() {
          _nowSecs = nowUnixSecs();
          _notifiedCurrentDue = false;
          _statusNotice = confirmationText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusNotice = 'Fehler: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openBehaviorMarkerDialog() async {
    final chosen = await showModalBottomSheet<DatapointFlag>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ereignis neutral markieren',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Wird mit dem aktuellen Skalenwert (${_sliderSud.round()}) im Verlauf vermerkt.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface
                      .withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(ctx, DatapointFlag.avoidanceOrRitual),
                child: const Text('Vermeidung / Ritual ausgeführt'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(ctx, DatapointFlag.safetyBehavior),
                child: const Text(
                  'Sicherheitsverhalten / Ersatzhandlung genutzt',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen == null) return;
    final label = chosen == DatapointFlag.avoidanceOrRitual
        ? 'Marker „Vermeidung / Ritual“ gespeichert.'
        : 'Marker „Sicherheitsverhalten“ gespeichert.';
    await _logPoint(chosen, label);
  }

  Future<void> _openFinishSheet() async {
    final item = widget.state.findItemById(widget.session.exposureItemId);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FinishExposureSheet(
        state: widget.state,
        session: widget.session,
        item: item,
        initialFinalSud: _sliderSud.round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final item = widget.state.findItemById(s.exposureItemId);
    final elapsedSecs = max(0, _nowSecs - s.startedAt);
    final sinceLastCheckIn = max(0, _nowSecs - _lastCheckInSecs());
    final remainingToNext = s.intervalSecs - sinceLastCheckIn;
    final checkInDue = remainingToNext <= 0;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(item?.title ?? 'Laufende Exposition'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _openFinishSheet,
              child: const Text('Beenden'),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Handy weglegen. Beim Intervall nur kurz den aktuellen Wert eintragen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                const Spacer(),
                Text(
                  formatDurationMmSs(elapsedSecs),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: checkInDue
                          ? scheme.primary.withValues(alpha: 0.22)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: checkInDue ? scheme.primary : scheme.outline,
                      ),
                    ),
                    child: Text(
                      checkInDue
                          ? 'Check-in fällig'
                          : 'Nächster Check-in in ${formatDurationMmSs(remainingToNext)}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: checkInDue ? scheme.primary : scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Einträge bisher: ${s.datapoints.length}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
                const Spacer(),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Aktuelle Anspannung',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${_sliderSud.round()} / ${s.scaleMax}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 8,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 14,
                            ),
                          ),
                          child: Slider(
                            value: _sliderSud,
                            min: 0,
                            max: s.scaleMax.toDouble(),
                            divisions: s.scaleMax == 10 ? 10 : 20,
                            onChanged: (v) => setState(() => _sliderSud = v),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _logPoint(
                                  DatapointFlag.checkIn,
                                  'Check-in (${_sliderSud.round()}) gespeichert.',
                                ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Check-in speichern'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _saving ? null : _openBehaviorMarkerDialog,
                  child: const Text(
                    'Vermeidung / Sicherheitsverhalten markieren',
                  ),
                ),
                if (_statusNotice != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _statusNotice!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinishExposureSheet extends StatefulWidget {
  const _FinishExposureSheet({
    required this.state,
    required this.session,
    required this.item,
    required this.initialFinalSud,
  });

  final AppState state;
  final ExposureSession session;
  final ExposureItem? item;
  final int initialFinalSud;

  @override
  State<_FinishExposureSheet> createState() => _FinishExposureSheetState();
}

class _FinishExposureSheetState extends State<_FinishExposureSheet> {
  SessionStatus _status = SessionStatus.completed;
  late double _finalSud;
  FearOutcome? _fearOccurred;
  final Set<int> _selectedSafetyBehaviorIds = {};
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _finalSud = widget.initialFinalSud.toDouble();
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
      await widget.state.core.finishExposureSession(
        input: FinishExposureSessionInput(
          sessionId: widget.session.id,
          status: _status,
          finalSudValue: _finalSud.round(),
          fearOccurred: _fearOccurred,
          usedSafetyBehaviorIds: Int64List.fromList(
            _selectedSafetyBehaviorIds.toList()..sort(),
          ),
          notes: _notesCtrl.text.trim(),
        ),
      );
      await widget.state.refreshAll();
      if (mounted) {
        Navigator.of(context).pop();
      }
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
    final activeSafetyBehaviors = (widget.item?.safetyBehaviors ?? const [])
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
              'Exposition abschließen',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SegmentedButton<SessionStatus>(
              segments: const [
                ButtonSegment(
                  value: SessionStatus.completed,
                  label: Text('Beendet'),
                ),
                ButtonSegment(
                  value: SessionStatus.aborted,
                  label: Text('Abgebrochen'),
                ),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Abschluss-Anspannung',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${_finalSud.round()} / ${widget.session.scaleMax}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            Slider(
              value: _finalSud,
              min: 0,
              max: widget.session.scaleMax.toDouble(),
              divisions: widget.session.scaleMax == 10 ? 10 : 20,
              onChanged: (v) => setState(() => _finalSud = v),
            ),
            if (widget.session.expectedFear.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Befürchtung: „${widget.session.expectedFear}“',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ist die Befürchtung eingetreten?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<FearOutcome>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: FearOutcome.no, label: Text('Nein')),
                  ButtonSegment(
                    value: FearOutcome.partially,
                    label: Text('Teilweise'),
                  ),
                  ButtonSegment(value: FearOutcome.yes, label: Text('Ja')),
                ],
                selected: _fearOccurred == null ? {} : {_fearOccurred!},
                onSelectionChanged: (s) =>
                    setState(() => _fearOccurred = s.isEmpty ? null : s.first),
              ),
            ],
            if (activeSafetyBehaviors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Genutztes Sicherheitsverhalten / Ersatzhandlungen (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: activeSafetyBehaviors.map((sb) {
                  final selected = _selectedSafetyBehaviorIds.contains(sb.id);
                  return FilterChip(
                    label: Text(sb.label),
                    selected: selected,
                    onSelected: (checked) {
                      setState(() {
                        if (checked) {
                          _selectedSafetyBehaviorIds.add(sb.id);
                        } else {
                          _selectedSafetyBehaviorIds.remove(sb.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Sachliche Notiz (optional)',
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
                  : const Text('Protokoll speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
