import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../src/rust/model.dart';

const List<Color> _kCurveColors = [
  Color(0xFF5B9BD5), // Neueste
  Color(0xFF64B5A6),
  Color(0xFFD4A359),
  Color(0xFF9B8AD4),
  Color(0xFFC97A7A),
];

class ItemCurvesScreen extends StatefulWidget {
  const ItemCurvesScreen({super.key, required this.state, required this.item});

  final AppState state;
  final ExposureItem item;

  @override
  State<ItemCurvesScreen> createState() => _ItemCurvesScreenState();
}

class _ItemCurvesScreenState extends State<ItemCurvesScreen> {
  List<ExposureSession> _sessions = const [];
  final Set<int> _visibleSessionIds = {};
  bool _loading = true;
  String? _error;
  bool _presentationLocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await widget.state.core.listExposureSessionsForItem(
        exposureItemId: widget.item.id,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _visibleSessionIds
          ..clear()
          ..addAll(list.take(5).map((s) => s.id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
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
      setState(() => _presentationLocked = false);
    }
  }

  Future<void> _deleteSession(ExposureSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Protokoll löschen?'),
        content: Text(
          'Übung vom ${formatTimestampShort(session.startedAt)} dauerhaft löschen?',
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

    await widget.state.core.deleteExposureSession(id: session.id);
    await _load();
  }

  String _safetyBehaviorName(int id) {
    for (final sb in widget.item.safetyBehaviors) {
      if (sb.id == id) return sb.label;
    }
    return 'Sicherheitsverhalten #$id';
  }

  @override
  Widget build(BuildContext context) {
    final visibleSessions = _sessions
        .where((s) => _visibleSessionIds.contains(s.id))
        .toList();

    return PopScope(
      canPop: !_presentationLocked,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !_presentationLocked,
          title: Text(widget.item.title),
          actions: [
            if (_presentationLocked)
              TextButton.icon(
                onPressed: _unlockPresentationMode,
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: const Text('Entsperren'),
              )
            else
              IconButton(
                tooltip: 'Vorzeige-Modus (Navigation sperren)',
                onPressed: () => setState(() => _presentationLocked = true),
                icon: const Icon(Icons.screen_lock_portrait_outlined),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : _sessions.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Noch keine abgeschlossenen Expositionen für dieses Thema.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  if (_presentationLocked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Vorzeige-Modus aktiv – Navigation in andere Bereiche ist gesperrt.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Überlagerte Verläufe (normiert 0–100 %)',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                '${visibleSessions.length} aktiv',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _HabituationCurvesPainter(
                                sessions: visibleSessions,
                                gridColor: Theme.of(context).colorScheme.outline
                                    .withValues(alpha: 0.45),
                                textColor: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Punkt = Check-in · Raute = Vermeidung / Sicherheitsverhalten · X = Abbruch',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: List.generate(_sessions.length, (idx) {
                      final s = _sessions[idx];
                      final visible = _visibleSessionIds.contains(s.id);
                      final colorIdx = visibleSessions.indexWhere(
                        (v) => v.id == s.id,
                      );
                      final dotColor = colorIdx >= 0
                          ? _kCurveColors[colorIdx % _kCurveColors.length]
                          : Colors.grey;

                      return FilterChip(
                        avatar: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: visible ? dotColor : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: dotColor),
                          ),
                        ),
                        label: Text(formatDateOnly(s.startedAt)),
                        selected: visible,
                        onSelected: (checked) {
                          setState(() {
                            if (checked) {
                              _visibleSessionIds.add(s.id);
                            } else {
                              _visibleSessionIds.remove(s.id);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  ..._sessions.map((s) {
                    final durSecs = (s.endedAt ?? s.startedAt) - s.startedAt;
                    final startSud = s.datapoints.isNotEmpty
                        ? s.datapoints.first.sudValue
                        : null;
                    final endSud = s.datapoints.isNotEmpty
                        ? s.datapoints.last.sudValue
                        : null;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    formatTimestampShort(s.startedAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                Text(
                                  s.status == SessionStatus.aborted
                                      ? 'Abgebrochen · ${formatDurationMmSs(durSecs)}'
                                      : formatDurationMmSs(durSecs),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                                if (!_presentationLocked)
                                  IconButton(
                                    tooltip: 'Protokoll löschen',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    onPressed: () => _deleteSession(s),
                                  ),
                              ],
                            ),
                            if (startSud != null && endSud != null)
                              Text(
                                'Anspannung: $startSud → $endSud (Skala ${s.scaleMax}, ${s.datapoints.length} Punkte)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (s.expectedFear.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Befürchtung: ${s.expectedFear}'
                                '${s.expectedConvictionPct != null ? ' (${s.expectedConvictionPct} %)' : ''}'
                                '${s.fearOccurred != null ? ' · Eingetreten: ${fearOutcomeLabel(s.fearOccurred!)}' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (s.usedSafetyBehaviorIds.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: s.usedSafetyBehaviorIds
                                    .map(
                                      (sbid) => Chip(
                                        label: Text(
                                          _safetyBehaviorName(sbid.toInt()),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            if (s.notes.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                s.notes,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _HabituationCurvesPainter extends CustomPainter {
  _HabituationCurvesPainter({
    required this.sessions,
    required this.gridColor,
    required this.textColor,
  });

  final List<ExposureSession> sessions;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPad = 34;
    const double rightPad = 12;
    const double topPad = 10;
    const double bottomPad = 24;

    final chartRect = Rect.fromLTRB(
      leftPad,
      topPad,
      max(leftPad + 1, size.width - rightPad),
      max(topPad + 1, size.height - bottomPad),
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizontale Hilfslinien (0, 25, 50, 75, 100 %)
    for (final pct in const [0, 25, 50, 75, 100]) {
      final y = chartRect.bottom - (pct / 100.0) * chartRect.height;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
      _drawText(
        canvas,
        '$pct',
        Offset(0, y - 6),
        width: leftPad - 6,
        align: TextAlign.right,
      );
    }

    if (sessions.isEmpty) return;

    // Maximale Dauer über alle sichtbaren Sessions (mindestens 5 Min für saubere Achse)
    int maxDurationSecs = 300;
    for (final s in sessions) {
      for (final dp in s.datapoints) {
        final dt = dp.recordedAt - s.startedAt;
        if (dt > maxDurationSecs) maxDurationSecs = dt;
      }
      if (s.endedAt != null) {
        final dt = s.endedAt! - s.startedAt;
        if (dt > maxDurationSecs) maxDurationSecs = dt;
      }
    }

    // X-Achsen-Labels (0 min, Mitte, Max)
    final maxMinutes = (maxDurationSecs / 60).ceil();
    final midMinutes = (maxMinutes / 2).round();
    _drawText(
      canvas,
      '0m',
      Offset(chartRect.left, chartRect.bottom + 6),
      width: 36,
      align: TextAlign.left,
    );
    _drawText(
      canvas,
      '${midMinutes}m',
      Offset(chartRect.center.dx - 20, chartRect.bottom + 6),
      width: 40,
      align: TextAlign.center,
    );
    _drawText(
      canvas,
      '${maxMinutes}m',
      Offset(chartRect.right - 40, chartRect.bottom + 6),
      width: 40,
      align: TextAlign.right,
    );

    // Älteste zuerst zeichnen, damit die neueste Kurve oben liegt
    for (int i = sessions.length - 1; i >= 0; i--) {
      final s = sessions[i];
      if (s.datapoints.isEmpty) continue;

      final baseColor = _kCurveColors[i % _kCurveColors.length];
      final opacity = i == 0 ? 1.0 : max(0.35, 0.85 - i * 0.14);
      final strokeWidth = i == 0 ? 2.8 : 1.8;

      final linePaint = Paint()
        ..color = baseColor.withValues(alpha: opacity)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final offsets = <Offset>[];

      for (int pIdx = 0; pIdx < s.datapoints.length; pIdx++) {
        final dp = s.datapoints[pIdx];
        final xFrac = ((dp.recordedAt - s.startedAt) / maxDurationSecs).clamp(
          0.0,
          1.0,
        );
        final yFrac = (dp.sudValue / max(1, s.scaleMax)).clamp(0.0, 1.0);

        final dx = chartRect.left + xFrac * chartRect.width;
        final dy = chartRect.bottom - yFrac * chartRect.height;
        final pt = Offset(dx, dy);
        offsets.add(pt);

        if (pIdx == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }

      if (offsets.length > 1) {
        canvas.drawPath(path, linePaint);
      }

      // Marker für Datenpunkte
      final dotFill = Paint()
        ..color = baseColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      final markerStroke = Paint()
        ..color = baseColor.withValues(alpha: opacity)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      for (int pIdx = 0; pIdx < s.datapoints.length; pIdx++) {
        final dp = s.datapoints[pIdx];
        final pt = offsets[pIdx];

        switch (dp.flag) {
          case DatapointFlag.checkIn:
            canvas.drawCircle(pt, i == 0 ? 3.8 : 2.8, dotFill);
          case DatapointFlag.avoidanceOrRitual:
          case DatapointFlag.safetyBehavior:
            final r = i == 0 ? 5.2 : 4.2;
            final diamond = Path()
              ..moveTo(pt.dx, pt.dy - r)
              ..lineTo(pt.dx + r, pt.dy)
              ..lineTo(pt.dx, pt.dy + r)
              ..lineTo(pt.dx - r, pt.dy)
              ..close();
            canvas.drawPath(diamond, markerStroke);
          case DatapointFlag.aborted:
            const r = 4.5;
            canvas.drawLine(
              Offset(pt.dx - r, pt.dy - r),
              Offset(pt.dx + r, pt.dy + r),
              markerStroke,
            );
            canvas.drawLine(
              Offset(pt.dx + r, pt.dy - r),
              Offset(pt.dx - r, pt.dy + r),
              markerStroke,
            );
        }
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double width,
    required TextAlign align,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 11),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _HabituationCurvesPainter oldDelegate) {
    return oldDelegate.sessions != sessions ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.textColor != textColor;
  }
}
