import 'package:flutter/material.dart';

import '../src/rust/model.dart';

const List<String> kCategoryPalette = [
  '#5B9BD5', // Ruhiges Blau
  '#64B5A6', // Salbei / Petrol
  '#D4A359', // Warmes Ocker
  '#C97A7A', // Gedecktes Altrosa
  '#9B8AD4', // Sanftes Lavendel
  '#7FA66B', // Moosgrün
  '#7D8FA3', // Schiefergrau
  '#C98A5B', // Terrakotta
];

Color parseHexColor(String hex, {Color fallback = const Color(0xFF5B9BD5)}) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length == 6) {
    final value = int.tryParse('FF$cleaned', radix: 16);
    if (value != null) return Color(value);
  } else if (cleaned.length == 8) {
    final value = int.tryParse(cleaned, radix: 16);
    if (value != null) return Color(value);
  }
  return fallback;
}

int nowUnixSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

int todayEpochDay() => dateTimeToEpochDay(DateTime.now());

int dateTimeToEpochDay(DateTime dt) {
  final utc = DateTime.utc(dt.year, dt.month, dt.day);
  return utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

DateTime epochDayToDateTime(int epochDay) {
  return DateTime.fromMillisecondsSinceEpoch(
    epochDay * Duration.millisecondsPerDay,
    isUtc: true,
  );
}

int daysInMonth(int year, int month) {
  return DateTime.utc(year, month + 1, 0).day;
}

FuzzyDate buildFuzzyDate({
  required DatePrecision precision,
  required int year,
  int month = 1,
  int day = 1,
  int quarter = 1,
  required bool isEnd,
}) {
  switch (precision) {
    case DatePrecision.day:
      final clampedDay = day.clamp(1, daysInMonth(year, month));
      return FuzzyDate(
        day: dateTimeToEpochDay(DateTime.utc(year, month, clampedDay)),
        precision: DatePrecision.day,
      );
    case DatePrecision.month:
      final targetDay = isEnd ? daysInMonth(year, month) : 1;
      return FuzzyDate(
        day: dateTimeToEpochDay(DateTime.utc(year, month, targetDay)),
        precision: DatePrecision.month,
      );
    case DatePrecision.quarter:
      final q = quarter.clamp(1, 4);
      final startMonth = (q - 1) * 3 + 1;
      final endMonth = startMonth + 2;
      final targetDate = isEnd
          ? DateTime.utc(year, endMonth, daysInMonth(year, endMonth))
          : DateTime.utc(year, startMonth, 1);
      return FuzzyDate(
        day: dateTimeToEpochDay(targetDate),
        precision: DatePrecision.quarter,
      );
    case DatePrecision.year:
      final targetDate = isEnd
          ? DateTime.utc(year, 12, 31)
          : DateTime.utc(year, 1, 1);
      return FuzzyDate(
        day: dateTimeToEpochDay(targetDate),
        precision: DatePrecision.year,
      );
  }
}

String formatDurationMmSs(int totalSeconds) {
  final clamped = totalSeconds < 0 ? 0 : totalSeconds;
  final mins = clamped ~/ 60;
  final secs = clamped % 60;
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

String formatTimestampShort(int unixSecs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000);
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$d.$m.${dt.year}, $h:$min';
}

String formatDateOnly(int unixSecs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000);
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  return '$d.$m.${dt.year}';
}

String formatEpochDay(int epochDay) {
  final dt = epochDayToDateTime(epochDay);
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  return '$d.$m.${dt.year}';
}

String formatFuzzyDate(FuzzyDate fd) {
  final dt = epochDayToDateTime(fd.day);
  switch (fd.precision) {
    case DatePrecision.day:
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      return '$d.$m.${dt.year}';
    case DatePrecision.month:
      final m = dt.month.toString().padLeft(2, '0');
      return 'ca. $m/${dt.year}';
    case DatePrecision.quarter:
      final q = ((dt.month - 1) ~/ 3) + 1;
      return 'ca. Q$q/${dt.year}';
    case DatePrecision.year:
      return 'ca. ${dt.year}';
  }
}

String datePrecisionLabel(DatePrecision p) {
  switch (p) {
    case DatePrecision.day:
      return 'Tag';
    case DatePrecision.month:
      return 'Monat';
    case DatePrecision.quarter:
      return 'Quartal';
    case DatePrecision.year:
      return 'Jahr';
  }
}

String severityLabel(Severity s) {
  switch (s) {
    case Severity.dormant:
      return 'Ruhend';
    case Severity.background:
      return 'Im Hintergrund';
    case Severity.moderate:
      return 'Belastend';
    case Severity.acute:
      return 'Akut';
  }
}

String contextEventTypeLabel(ContextEventType t) {
  switch (t) {
    case ContextEventType.clinic:
      return 'Klinik';
    case ContextEventType.medication:
      return 'Medikation';
    case ContextEventType.therapy:
      return 'Therapie';
    case ContextEventType.life:
      return 'Leben';
  }
}

Color contextEventColor(ContextEventType t) {
  switch (t) {
    case ContextEventType.clinic:
      return const Color(0xFF64B5A6);
    case ContextEventType.medication:
      return const Color(0xFFD4A359);
    case ContextEventType.therapy:
      return const Color(0xFF5B9BD5);
    case ContextEventType.life:
      return const Color(0xFF9B8AD4);
  }
}

String fearOutcomeLabel(FearOutcome outcome) {
  switch (outcome) {
    case FearOutcome.no:
      return 'Nein';
    case FearOutcome.partially:
      return 'Teilweise';
    case FearOutcome.yes:
      return 'Ja';
  }
}

String urgeOutcomeLabel(UrgeOutcome outcome) {
  switch (outcome) {
    case UrgeOutcome.running:
      return 'Läuft';
    case UrgeOutcome.subsided:
      return 'Drang abgeklungen';
    case UrgeOutcome.extended:
      return 'Verlängert';
    case UrgeOutcome.performed:
      return 'Ausgeführt';
  }
}
