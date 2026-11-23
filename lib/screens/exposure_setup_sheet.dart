import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/background_timer.dart';
import '../src/rust/model.dart';

class ExposureSetupSheet extends StatefulWidget {
  const ExposureSetupSheet({
    super.key,
    required this.state,
    required this.item,
  });

  final AppState state;
  final ExposureItem item;

  @override
  State<ExposureSetupSheet> createState() => _ExposureSetupSheetState();
}

class _ExposureSetupSheetState extends State<ExposureSetupSheet> {
  late int _scaleMax;
  late int _intervalSecs;
  late double _initialSud;
  late final TextEditingController _fearCtrl;
  bool _trackConviction = false;
  double _convictionPct = 70;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scaleMax = widget.state.defaultScaleMax;
    _intervalSecs = widget.state.defaultIntervalSecs;
    _initialSud = _scaleMax == 10 ? 6 : 60;
    _fearCtrl = TextEditingController(text: widget.item.coreFear);
    _trackConviction = widget.item.coreFear.isNotEmpty;
  }

  @override
  void dispose() {
    _fearCtrl.dispose();
    super.dispose();
  }

  void _changeScale(int nextScale) {
    if (nextScale == _scaleMax) return;
    setState(() {
      if (nextScale == 10) {
        _initialSud = (_initialSud / 10).round().clamp(0, 10).toDouble();
      } else {
        _initialSud = (_initialSud * 10).round().clamp(0, 100).toDouble();
      }
      _scaleMax = nextScale;
    });
  }

  Future<void> _start() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await BackgroundTimerBridge.requestNotificationPermission();

      final fearText = _fearCtrl.text.trim();
      await widget.state.core.startExposureSession(
        input: StartExposureSessionInput(
          exposureItemId: widget.item.id,
          intervalSecs: _intervalSecs,
          scaleMax: _scaleMax,
          initialSud: _initialSud.round(),
          expectedFear: fearText,
          expectedConvictionPct: (fearText.isNotEmpty && _trackConviction)
              ? _convictionPct.round()
              : null,
        ),
      );
      await widget.state.refreshAll();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.item.triggerDesc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Auslöser: ${widget.item.triggerDesc}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.72),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Start-Anspannung',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${_initialSud.round()} / $_scaleMax',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            Slider(
              value: _initialSud,
              min: 0,
              max: _scaleMax.toDouble(),
              divisions: _scaleMax == 10 ? 10 : 20,
              label: '${_initialSud.round()}',
              onChanged: (v) => setState(() => _initialSud = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check-in-Intervall',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 180, label: Text('3m')),
                          ButtonSegment(value: 300, label: Text('5m')),
                          ButtonSegment(value: 600, label: Text('10m')),
                        ],
                        selected: {_intervalSecs},
                        onSelectionChanged: (s) =>
                            setState(() => _intervalSecs = s.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Skala',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 10, label: Text('10')),
                        ButtonSegment(value: 100, label: Text('100')),
                      ],
                      selected: {_scaleMax},
                      onSelectionChanged: (s) => _changeScale(s.first),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _fearCtrl,
              decoration: const InputDecoration(
                labelText: 'Konkrete Befürchtung (optional)',
                hintText: 'Was glaubst du, passiert schlimmstenfalls?',
              ),
              onChanged: (text) {
                setState(() {
                  if (text.trim().isEmpty) {
                    _trackConviction = false;
                  }
                });
              },
            ),
            if (_fearCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Überzeugungsgrad erfassen'),
                subtitle: _trackConviction
                    ? Text('${_convictionPct.round()} %')
                    : null,
                value: _trackConviction,
                onChanged: (v) => setState(() => _trackConviction = v),
              ),
              if (_trackConviction)
                Slider(
                  value: _convictionPct,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_convictionPct.round()} %',
                  onChanged: (v) => setState(() => _convictionPct = v),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submitting ? null : _start,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Exposition starten'),
            ),
          ],
        ),
      ),
    );
  }
}
