import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/core.dart';
import '../src/rust/model.dart';
import 'background_timer.dart';
import 'format.dart';

class AppState extends ChangeNotifier {
  AppCore? _core;
  String? _dbPath;
  String? _activePassphrase;

  bool _initializing = true;
  bool _dbExists = false;
  bool _busy = false;
  String? _error;

  List<CategoryGroup> _catalog = const [];
  List<CategoryGroup> _catalogWithArchived = const [];
  ExposureSession? _activeExposureSession;
  UrgeDelay? _activeUrgeDelay;

  // Standardwerte für Expositionen (später auch über app_meta persistierbar)
  int defaultScaleMax = 100;
  int defaultIntervalSecs = 300;

  bool get initializing => _initializing;
  bool get dbExists => _dbExists;
  bool get isUnlocked => _core != null;
  bool get busy => _busy;
  String? get error => _error;
  String? get dbPath => _dbPath;

  AppCore get core {
    final c = _core;
    if (c == null) {
      throw StateError('Datenbank ist nicht entsperrt.');
    }
    return c;
  }

  List<CategoryGroup> get catalog => _catalog;
  List<CategoryGroup> get catalogWithArchived => _catalogWithArchived;
  ExposureSession? get activeExposureSession => _activeExposureSession;
  UrgeDelay? get activeUrgeDelay => _activeUrgeDelay;

  Future<void> init() async {
    _initializing = true;
    notifyListeners();

    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _dbPath = p.join(dir.path, 'expolog.db');
      _dbExists = await File(_dbPath!).exists();
    } catch (e) {
      _error = 'Speicherpfad konnte nicht ermittelt werden: $e';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<bool> unlockOrCreate(String passphrase) async {
    final path = _dbPath;
    if (path == null) return false;

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final opened = await AppCore.open(dbPath: path, passphrase: passphrase);
      _core = opened;
      _activePassphrase = passphrase;
      _dbExists = true;
      await refreshAll();
      return true;
    } catch (_) {
      _error = _dbExists
          ? 'Passphrase ungültig oder Datenbank konnte nicht geöffnet werden.'
          : 'Datenbank konnte nicht angelegt werden.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool verifyPassphrase(String candidate) {
    return _activePassphrase != null && candidate == _activePassphrase;
  }

  void lock() {
    _core?.dispose();
    _core = null;
    _activePassphrase = null;
    _catalog = const [];
    _catalogWithArchived = const [];
    _activeExposureSession = null;
    _activeUrgeDelay = null;
    _error = null;
    // Laufender Hintergrund-Timer bleibt bewusst aktiv, falls eine Übung/Aufschub läuft
    notifyListeners();
  }

  Future<void> refreshAll() async {
    final c = _core;
    if (c == null) return;

    final results = await Future.wait([
      c.listCatalog(includeArchived: false),
      c.listCatalog(includeArchived: true),
      c.getActiveExposureSession(),
      c.getActiveUrgeDelay(),
    ]);

    _catalog = results[0] as List<CategoryGroup>;
    _catalogWithArchived = results[1] as List<CategoryGroup>;
    _activeExposureSession = results[2] as ExposureSession?;
    _activeUrgeDelay = results[3] as UrgeDelay?;

    await _syncBackgroundTimer();
    notifyListeners();
  }

  Future<void> _syncBackgroundTimer() async {
    final activeExp = _activeExposureSession;
    if (activeExp != null) {
      int lastCheckInSecs = activeExp.startedAt;
      for (int i = activeExp.datapoints.length - 1; i >= 0; i--) {
        if (activeExp.datapoints[i].flag == DatapointFlag.checkIn) {
          lastCheckInSecs = activeExp.datapoints[i].recordedAt;
          break;
        }
      }

      final interval = activeExp.intervalSecs;
      final now = nowUnixSecs();
      int nextTriggerSecs = lastCheckInSecs + interval;
      if (nextTriggerSecs <= now) {
        final nextSlot = ((now - lastCheckInSecs) ~/ interval) + 1;
        nextTriggerSecs = lastCheckInSecs + nextSlot * interval;
      }

      await BackgroundTimerBridge.startOrUpdate(
        sessionKey: 'exp_${activeExp.id}_$lastCheckInSecs',
        nextTriggerAtSecs: nextTriggerSecs,
        repeatIntervalSecs: interval,
      );
      return;
    }

    final activeUrge = _activeUrgeDelay;
    if (activeUrge != null) {
      final targetEndSecs =
          activeUrge.startedAt + activeUrge.targetDurationSecs;
      if (targetEndSecs > nowUnixSecs()) {
        await BackgroundTimerBridge.startOrUpdate(
          sessionKey: 'urge_${activeUrge.id}',
          nextTriggerAtSecs: targetEndSecs,
          repeatIntervalSecs: 0,
        );
        return;
      }
    }

    await BackgroundTimerBridge.stop();
  }

  Future<void> refreshCatalog() async {
    final c = _core;
    if (c == null) return;

    final results = await Future.wait([
      c.listCatalog(includeArchived: false),
      c.listCatalog(includeArchived: true),
    ]);

    _catalog = results[0];
    _catalogWithArchived = results[1];
    notifyListeners();
  }

  void setDefaultScaleMax(int scaleMax) {
    if (scaleMax == 10 || scaleMax == 100) {
      defaultScaleMax = scaleMax;
      notifyListeners();
    }
  }

  void setDefaultIntervalSecs(int secs) {
    if (secs > 0) {
      defaultIntervalSecs = secs;
      notifyListeners();
    }
  }

  ExposureItem? findItemById(int id) {
    for (final group in _catalogWithArchived) {
      for (final item in group.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _core?.dispose();
    super.dispose();
  }
}
