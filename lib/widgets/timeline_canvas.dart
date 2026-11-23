import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../src/rust/model.dart';

const double kTimelineLabelWidth = 118.0;
const double kTimelineAxisHeight = 28.0;
const double kTimelineContextHeight = 46.0;
const double kTimelineHeaderHeight =
    kTimelineAxisHeight + kTimelineContextHeight;
const double kTimelineMinSpanDays = 21.0;
const double kTimelineMaxSpanDays = 3650.0;

class _TimelineRow {
  const _TimelineRow({
    required this.top,
    required this.height,
    required this.lane,
    this.item,
    required this.isExpandedCategory,
  });

  final double top;
  final double height;
  final TimelineCategoryLane lane;
  final TimelineItemTrack? item;
  final bool isExpandedCategory;

  double get bottom => top + height;
  bool get isCategoryRow => item == null;
}

class _PackedContextRect {
  const _PackedContextRect({
    required this.event,
    required this.rect,
    required this.startX,
  });

  final ContextEvent event;
  final Rect rect;
  final double startX;
}

class TimelineCanvas extends StatefulWidget {
  const TimelineCanvas({
    super.key,
    required this.viewportData,
    required this.startDay,
    required this.spanDays,
    required this.todayDay,
    required this.expandedCategoryIds,
    required this.onViewportChanged,
    required this.onToggleCategory,
    required this.onTapItem,
    required this.onTapPhase,
    required this.onTapContextEvent,
  });

  final TimelineViewportData viewportData;
  final double startDay;
  final double spanDays;
  final int todayDay;
  final Set<int> expandedCategoryIds;
  final void Function(double startDay, double spanDays) onViewportChanged;
  final ValueChanged<int> onToggleCategory;
  final ValueChanged<int> onTapItem;
  final void Function(int exposureItemId, TimelinePhase phase) onTapPhase;
  final ValueChanged<ContextEvent> onTapContextEvent;

  @override
  State<TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<TimelineCanvas> {
  double _verticalScrollOffset = 0.0;

  double _scaleStartSpan = 365.0;
  double _scaleStartDay = 0.0;
  Offset _scaleStartFocal = Offset.zero;
  double _scaleStartScroll = 0.0;

  List<_TimelineRow> _buildRows() {
    final rows = <_TimelineRow>[];
    double y = 0.0;

    for (final lane in widget.viewportData.groups) {
      final expanded = widget.expandedCategoryIds.contains(lane.categoryId);
      if (!expanded) {
        final stripCount = max(1, lane.items.length);
        final height = max(46.0, 16.0 + stripCount * 8.0);
        rows.add(
          _TimelineRow(
            top: y,
            height: height,
            lane: lane,
            isExpandedCategory: false,
          ),
        );
        y += height;
      } else {
        const headerHeight = 36.0;
        rows.add(
          _TimelineRow(
            top: y,
            height: headerHeight,
            lane: lane,
            isExpandedCategory: true,
          ),
        );
        y += headerHeight;

        for (final item in lane.items) {
          const itemHeight = 46.0;
          rows.add(
            _TimelineRow(
              top: y,
              height: itemHeight,
              lane: lane,
              item: item,
              isExpandedCategory: true,
            ),
          );
          y += itemHeight;
        }
      }
    }

    return rows;
  }

  List<_PackedContextRect> _packContextEvents(double totalWidth) {
    final timelineWidth = max(1.0, totalWidth - kTimelineLabelWidth);
    final result = <_PackedContextRect>[];
    final laneEndX = <double>[-1e9, -1e9];
    const subLaneHeight = 19.0;
    const subLaneGap = 3.0;
    const topPad = kTimelineAxisHeight + 3.0;

    double dayToX(double d) {
      return kTimelineLabelWidth +
          ((d - widget.startDay) / widget.spanDays) * timelineWidth;
    }

    for (final ev in widget.viewportData.contextEvents) {
      final startX = dayToX(ev.start.day.toDouble());
      double endX;
      if (ev.isOngoing) {
        endX = dayToX(max(ev.start.day + 1, widget.todayDay).toDouble());
      } else if (ev.end != null) {
        endX = dayToX((ev.end!.day + 1).toDouble());
      } else {
        endX = startX + 76.0;
      }

      final visualLeft = startX.clamp(kTimelineLabelWidth, totalWidth);
      final visualRight = max(
        visualLeft + 26.0,
        endX,
      ).clamp(kTimelineLabelWidth + 16.0, totalWidth);

      int chosenLane = 0;
      if (laneEndX[0] + 4.0 <= visualLeft) {
        chosenLane = 0;
      } else if (laneEndX[1] + 4.0 <= visualLeft) {
        chosenLane = 1;
      } else {
        chosenLane = laneEndX[0] <= laneEndX[1] ? 0 : 1;
      }

      laneEndX[chosenLane] = visualRight;
      final top = topPad + chosenLane * (subLaneHeight + subLaneGap);

      result.add(
        _PackedContextRect(
          event: ev,
          rect: Rect.fromLTRB(
            visualLeft,
            top,
            visualRight,
            top + subLaneHeight,
          ),
          startX: startX,
        ),
      );
    }

    return result;
  }

  double _maxScroll(List<_TimelineRow> rows, double totalHeight) {
    final totalContent = rows.isEmpty ? 0.0 : rows.last.bottom + 24.0;
    final visible = max(0.0, totalHeight - kTimelineHeaderHeight);
    return max(0.0, totalContent - visible);
  }

  void _handlePointerSignal(PointerSignalEvent event, Size size) {
    if (event is! PointerScrollEvent) return;
    final timelineWidth = max(1.0, size.width - kTimelineLabelWidth);
    final localX = event.localPosition.dx;

    // Mausrad über den Beschriftungen scrollt vertikal, über dem Zeitstrahl zoomt es 1D horizontal
    if (localX < kTimelineLabelWidth) {
      final rows = _buildRows();
      final maxScroll = _maxScroll(rows, size.height);
      setState(() {
        _verticalScrollOffset = (_verticalScrollOffset + event.scrollDelta.dy)
            .clamp(0.0, maxScroll);
      });
      return;
    }

    final zoomFactor = event.scrollDelta.dy > 0 ? 1.18 : (1.0 / 1.18);
    final nextSpan = (widget.spanDays * zoomFactor).clamp(
      kTimelineMinSpanDays,
      kTimelineMaxSpanDays,
    );
    final frac = ((localX - kTimelineLabelWidth) / timelineWidth).clamp(
      0.0,
      1.0,
    );
    final focalDay = widget.startDay + frac * widget.spanDays;
    final nextStart = focalDay - frac * nextSpan;
    widget.onViewportChanged(nextStart, nextSpan);
  }

  void _handleTapUp(
    TapUpDetails details,
    Size size,
    List<_TimelineRow> rows,
    List<_PackedContextRect> packedContext,
  ) {
    final pos = details.localPosition;

    // 1. Kontext-Spur oben
    if (pos.dy >= kTimelineAxisHeight && pos.dy < kTimelineHeaderHeight) {
      for (int i = packedContext.length - 1; i >= 0; i--) {
        if (packedContext[i].rect.inflate(4).contains(pos)) {
          widget.onTapContextEvent(packedContext[i].event);
          return;
        }
      }
      return;
    }

    if (pos.dy < kTimelineHeaderHeight) return;

    // 2. Spuren-Bereich
    final contentY = pos.dy - kTimelineHeaderHeight + _verticalScrollOffset;
    _TimelineRow? hitRow;
    for (final row in rows) {
      if (contentY >= row.top && contentY < row.bottom) {
        hitRow = row;
        break;
      }
    }
    if (hitRow == null) return;

    if (hitRow.isCategoryRow) {
      widget.onToggleCategory(hitRow.lane.categoryId);
      return;
    }

    final item = hitRow.item!;
    if (pos.dx < kTimelineLabelWidth) {
      widget.onTapItem(item.exposureItemId);
      return;
    }

    // Prüfen, ob eine konkrete Phase angetippt wurde
    final timelineWidth = max(1.0, size.width - kTimelineLabelWidth);
    final tappedDay =
        widget.startDay +
        ((pos.dx - kTimelineLabelWidth) / timelineWidth) * widget.spanDays;

    for (int i = item.phases.length - 1; i >= 0; i--) {
      final phase = item.phases[i];
      final startD = phase.start.day.toDouble();
      final endD = phase.end != null
          ? max(startD + 1.0, phase.end!.day.toDouble() + 1.0)
          : max(startD + 1.0, widget.todayDay.toDouble() + 1.0);
      // Toleranz von ~10px auf der Zeitachse für schmale Balken
      final dayTolerance = (10.0 / timelineWidth) * widget.spanDays;
      if (tappedDay >= startD - dayTolerance &&
          tappedDay <= endD + dayTolerance) {
        widget.onTapPhase(item.exposureItemId, phase);
        return;
      }
    }

    widget.onTapItem(item.exposureItemId);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rows = _buildRows();
        final maxScroll = _maxScroll(rows, size.height);
        final clampedScroll = _verticalScrollOffset.clamp(0.0, maxScroll);
        if (clampedScroll != _verticalScrollOffset) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _verticalScrollOffset = clampedScroll);
            }
          });
        }
        final packedContext = _packContextEvents(size.width);

        return Listener(
          onPointerSignal: (ev) => _handlePointerSignal(ev, size),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) =>
                _handleTapUp(details, size, rows, packedContext),
            onScaleStart: (details) {
              _scaleStartSpan = widget.spanDays;
              _scaleStartDay = widget.startDay;
              _scaleStartFocal = details.localFocalPoint;
              _scaleStartScroll = clampedScroll;
            },
            onScaleUpdate: (details) {
              final timelineWidth = max(1.0, size.width - kTimelineLabelWidth);
              final nextSpan = (_scaleStartSpan / details.scale).clamp(
                kTimelineMinSpanDays,
                kTimelineMaxSpanDays,
              );
              final focalFracStart =
                  ((_scaleStartFocal.dx - kTimelineLabelWidth) / timelineWidth)
                      .clamp(0.0, 1.0);
              final focalDay =
                  _scaleStartDay + focalFracStart * _scaleStartSpan;
              final focalFracNow =
                  ((details.localFocalPoint.dx - kTimelineLabelWidth) /
                          timelineWidth)
                      .clamp(0.0, 1.0);
              final nextStart = focalDay - focalFracNow * nextSpan;

              final dy = details.localFocalPoint.dy - _scaleStartFocal.dy;
              final nextScroll = (_scaleStartScroll - dy).clamp(0.0, maxScroll);

              if ((nextScroll - _verticalScrollOffset).abs() > 0.25) {
                setState(() => _verticalScrollOffset = nextScroll);
              }
              widget.onViewportChanged(nextStart, nextSpan);
            },
            child: CustomPaint(
              size: size,
              painter: _TimelinePainter(
                rows: rows,
                packedContext: packedContext,
                startDay: widget.startDay,
                spanDays: widget.spanDays,
                todayDay: widget.todayDay,
                verticalScrollOffset: clampedScroll,
                theme: Theme.of(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.rows,
    required this.packedContext,
    required this.startDay,
    required this.spanDays,
    required this.todayDay,
    required this.verticalScrollOffset,
    required this.theme,
  });

  final List<_TimelineRow> rows;
  final List<_PackedContextRect> packedContext;
  final double startDay;
  final double spanDays;
  final int todayDay;
  final double verticalScrollOffset;
  final ThemeData theme;

  static const List<String> _monthShort = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  double _dayToX(double day, double timelineWidth) {
    return kTimelineLabelWidth + ((day - startDay) / spanDays) * timelineWidth;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scheme = theme.colorScheme;
    final timelineWidth = max(1.0, size.width - kTimelineLabelWidth);
    final dividerPaint = Paint()
      ..color = scheme.outline.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    // Hintergrund der linken Spalte
    canvas.drawRect(
      Rect.fromLTWH(0, 0, kTimelineLabelWidth, size.height),
      Paint()..color = scheme.surface.withValues(alpha: 0.55),
    );

    // 1. Zeitgitter & Kontext-Hilfslinien über volle Höhe (im Timeline-Bereich)
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(kTimelineLabelWidth, 0, size.width, size.height),
    );
    _paintTimeGridAndHeader(canvas, size, timelineWidth);
    _paintContextReferenceLines(canvas, size);
    _paintTodayLine(canvas, size, timelineWidth);
    canvas.restore();

    // 2. Scrollbare Kategorie- und Themen-Spuren
    final lanesClip = Rect.fromLTRB(
      0,
      kTimelineHeaderHeight,
      size.width,
      size.height,
    );
    canvas.save();
    canvas.clipRect(lanesClip);
    canvas.translate(0, kTimelineHeaderHeight - verticalScrollOffset);

    for (final row in rows) {
      if (row.bottom < verticalScrollOffset ||
          row.top > verticalScrollOffset + lanesClip.height) {
        continue;
      }

      final catColor = parseHexColor(row.lane.colorHex);

      // Trennlinie unten
      canvas.drawLine(
        Offset(0, row.bottom),
        Offset(size.width, row.bottom),
        dividerPaint,
      );

      if (row.isCategoryRow) {
        _paintCategoryLabel(canvas, row, catColor);
        if (!row.isExpandedCategory) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTRB(kTimelineLabelWidth, row.top, size.width, row.bottom),
          );
          _paintCollapsedBundle(canvas, row, catColor, timelineWidth);
          canvas.restore();
        }
      } else {
        _paintItemLabel(canvas, row, catColor);
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(kTimelineLabelWidth, row.top, size.width, row.bottom),
        );
        _paintExpandedItemTrack(canvas, row, catColor, timelineWidth);
        canvas.restore();
      }
    }
    canvas.restore();

    // 3. Fixierter Header-Hintergrund (Zeitachse + Kontext-Spur)
    final headerBg = Paint()..color = theme.scaffoldBackgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, kTimelineHeaderHeight),
      headerBg,
    );

    // Header-Labels links
    _drawSingleLineText(
      canvas,
      'Zeitraum',
      const Offset(10, 6),
      kTimelineLabelWidth - 16,
      TextStyle(
        color: scheme.onSurface.withValues(alpha: 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    _drawSingleLineText(
      canvas,
      'Kontext',
      const Offset(10, kTimelineAxisHeight + 14),
      kTimelineLabelWidth - 16,
      TextStyle(
        color: scheme.onSurface.withValues(alpha: 0.72),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );

    // Zeitachsen-Labels & Kontext-Chips erneut sauber auf dem Header-Hintergrund
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(kTimelineLabelWidth, 0, size.width, kTimelineHeaderHeight),
    );
    _paintTimeHeaderLabels(canvas, timelineWidth);
    _paintContextChips(canvas);
    canvas.restore();

    // Trennlinien für Header und linke Spalte
    canvas.drawLine(
      const Offset(0, kTimelineAxisHeight),
      Offset(size.width, kTimelineAxisHeight),
      dividerPaint,
    );
    canvas.drawLine(
      const Offset(0, kTimelineHeaderHeight),
      Offset(size.width, kTimelineHeaderHeight),
      Paint()
        ..color = scheme.outline.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      const Offset(kTimelineLabelWidth, 0),
      Offset(kTimelineLabelWidth, size.height),
      dividerPaint,
    );
  }

  List<(double, String)> _computeTicks(double timelineWidth) {
    final ticks = <(double, String)>[];
    final startDt = epochDayToDateTime(startDay.floor());
    final endDt = epochDayToDateTime((startDay + spanDays).ceil());

    if (spanDays > 540) {
      // Jahres-Ticks
      final yearStep = spanDays > 2200 ? 2 : 1;
      int y = startDt.year;
      if (yearStep == 2 && y.isOdd) y -= 1;
      while (y <= endDt.year + 1) {
        final d = dateTimeToEpochDay(DateTime.utc(y, 1, 1)).toDouble();
        ticks.add((d, '$y'));
        y += yearStep;
      }
    } else if (spanDays > 110) {
      // Monats-Ticks
      int monthStep = 1;
      if (spanDays > 320) {
        monthStep = 3;
      } else if (spanDays > 200) {
        monthStep = 2;
      }
      int y = startDt.year;
      int m = ((startDt.month - 1) ~/ monthStep) * monthStep + 1;
      while (DateTime.utc(
        y,
        m,
        1,
      ).isBefore(endDt.add(const Duration(days: 32)))) {
        final d = dateTimeToEpochDay(DateTime.utc(y, m, 1)).toDouble();
        final shortY = (y % 100).toString().padLeft(2, '0');
        final label = m == 1
            ? '${_monthShort[m - 1]} $shortY'
            : _monthShort[m - 1];
        ticks.add((d, label));
        m += monthStep;
        if (m > 12) {
          m -= 12;
          y += 1;
        }
      }
    } else {
      // Wochen-Ticks (Montags)
      int stepDays = spanDays > 60 ? 14 : 7;
      int d = startDay.floor();
      // Auf nächsten Montag ausrichten (1970-01-01 war Donnerstag -> +3 = Montag)
      final offset = (d + 3) % 7;
      d -= offset;
      final endDay = (startDay + spanDays).ceil() + stepDays;
      while (d <= endDay) {
        final dt = epochDayToDateTime(d);
        final label =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
        ticks.add((d.toDouble(), label));
        d += stepDays;
      }
    }

    return ticks;
  }

  void _paintTimeGridAndHeader(Canvas canvas, Size size, double timelineWidth) {
    final ticks = _computeTicks(timelineWidth);
    final gridPaint = Paint()
      ..color = theme.colorScheme.outline.withValues(alpha: 0.20)
      ..strokeWidth = 1.0;

    for (final (day, _) in ticks) {
      final x = _dayToX(day, timelineWidth);
      if (x < kTimelineLabelWidth - 2 || x > size.width + 2) continue;
      canvas.drawLine(
        Offset(x, kTimelineHeaderHeight),
        Offset(x, size.height),
        gridPaint,
      );
    }
  }

  void _paintTimeHeaderLabels(Canvas canvas, double timelineWidth) {
    final ticks = _computeTicks(timelineWidth);
    final style = TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
      fontSize: 11,
    );
    final tickPaint = Paint()
      ..color = theme.colorScheme.outline.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    double lastLabelX = -1e9;
    for (final (day, label) in ticks) {
      final x = _dayToX(day, timelineWidth);
      if (x < kTimelineLabelWidth - 40) continue;
      canvas.drawLine(
        Offset(x, kTimelineAxisHeight - 6),
        Offset(x, kTimelineAxisHeight),
        tickPaint,
      );
      if (x - lastLabelX >= 52.0) {
        _drawSingleLineText(canvas, label, Offset(x + 4, 6), 54, style);
        lastLabelX = x;
      }
    }
  }

  void _paintContextReferenceLines(Canvas canvas, Size size) {
    for (final item in packedContext) {
      final color = contextEventColor(item.event.eventType);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 1.0;

      _drawDashedVerticalLine(
        canvas,
        item.startX,
        kTimelineHeaderHeight,
        size.height,
        paint,
      );
    }
  }

  void _paintContextChips(Canvas canvas) {
    for (final item in packedContext) {
      final color = contextEventColor(item.event.eventType);
      final rrect = RRect.fromRectAndRadius(
        item.rect,
        const Radius.circular(5),
      );
      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.26));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      if (item.rect.width >= 30) {
        _drawSingleLineText(
          canvas,
          item.event.title,
          Offset(item.rect.left + 5, item.rect.top + 3),
          item.rect.width - 8,
          TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        );
      }
    }
  }

  void _paintTodayLine(Canvas canvas, Size size, double timelineWidth) {
    final x = _dayToX(todayDay.toDouble(), timelineWidth);
    if (x < kTimelineLabelWidth || x > size.width) return;

    canvas.drawLine(
      Offset(x, kTimelineHeaderHeight),
      Offset(x, size.height),
      Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.65)
        ..strokeWidth = 1.4,
    );
  }

  void _paintCategoryLabel(Canvas canvas, _TimelineRow row, Color catColor) {
    final scheme = theme.colorScheme;
    final cy = row.top + row.height / 2;

    // Aufklapp-Pfeil (einfaches Dreieck)
    final arrow = Path();
    if (row.isExpandedCategory) {
      arrow
        ..moveTo(9, cy - 3)
        ..lineTo(17, cy - 3)
        ..lineTo(13, cy + 3)
        ..close();
    } else {
      arrow
        ..moveTo(10, cy - 4)
        ..lineTo(16, cy)
        ..lineTo(10, cy + 4)
        ..close();
    }
    canvas.drawPath(
      arrow,
      Paint()..color = scheme.onSurface.withValues(alpha: 0.72),
    );

    canvas.drawCircle(Offset(25, cy), 4.5, Paint()..color = catColor);

    _drawSingleLineText(
      canvas,
      row.lane.name,
      Offset(35, cy - 8),
      kTimelineLabelWidth - 40,
      TextStyle(
        color: scheme.onSurface,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );

    if (!row.isExpandedCategory) {
      _drawSingleLineText(
        canvas,
        '${row.lane.items.length} Themen',
        Offset(35, cy + 6),
        kTimelineLabelWidth - 40,
        TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.52),
          fontSize: 10,
        ),
      );
    }
  }

  void _paintItemLabel(Canvas canvas, _TimelineRow row, Color catColor) {
    final item = row.item!;
    final scheme = theme.colorScheme;
    final cy = row.top + row.height / 2;

    canvas.drawRect(
      Rect.fromLTWH(10, row.top + 8, 2.5, row.height - 16),
      Paint()..color = catColor.withValues(alpha: 0.55),
    );

    _drawSingleLineText(
      canvas,
      item.title,
      Offset(18, cy - 7),
      kTimelineLabelWidth - 24,
      TextStyle(color: scheme.onSurface.withValues(alpha: 0.88), fontSize: 12),
    );
  }

  void _paintCollapsedBundle(
    Canvas canvas,
    _TimelineRow row,
    Color catColor,
    double timelineWidth,
  ) {
    final items = row.lane.items;
    if (items.isEmpty) return;

    const stripH = 5.5;
    const stripGap = 2.5;
    final totalH = items.length * stripH + (items.length - 1) * stripGap;
    final startY = row.top + (row.height - totalH) / 2;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final y = startY + i * (stripH + stripGap);

      for (final phase in item.phases) {
        final x1 = _dayToX(phase.start.day.toDouble(), timelineWidth);
        final endDayVal = phase.end != null
            ? max(phase.start.day + 1, phase.end!.day + 1).toDouble()
            : max(phase.start.day + 1, todayDay + 1).toDouble();
        final x2 = max(x1 + 3.0, _dayToX(endDayVal, timelineWidth));

        if (phase.severity == Severity.dormant) {
          canvas.drawLine(
            Offset(x1, y + stripH / 2),
            Offset(x2, y + stripH / 2),
            Paint()
              ..color = catColor.withValues(alpha: 0.22)
              ..strokeWidth = 1.2,
          );
          continue;
        }

        final alpha = _severityAlpha(phase.severity);
        final rect = Rect.fromLTRB(x1, y, x2, y + stripH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = catColor.withValues(alpha: alpha),
        );
      }
    }
  }

  void _paintExpandedItemTrack(
    Canvas canvas,
    _TimelineRow row,
    Color catColor,
    double timelineWidth,
  ) {
    final item = row.item!;
    final cy = row.top + row.height / 2;

    for (final phase in item.phases) {
      final x1 = _dayToX(phase.start.day.toDouble(), timelineWidth);
      final endDayVal = phase.end != null
          ? max(phase.start.day + 1, phase.end!.day + 1).toDouble()
          : max(phase.start.day + 1, todayDay + 1).toDouble();
      final x2 = max(x1 + 5.0, _dayToX(endDayVal, timelineWidth));

      final barHeight = _severityHeight(phase.severity);
      final alpha = _severityAlpha(phase.severity);
      final rect = Rect.fromLTRB(
        x1,
        cy - barHeight / 2,
        x2,
        cy + barHeight / 2,
      );

      final fuzzyStart = phase.start.precision != DatePrecision.day;
      final fuzzyEnd =
          phase.end != null && phase.end!.precision != DatePrecision.day;
      final ongoing = phase.end == null;

      final barColor = catColor.withValues(alpha: alpha);

      if (fuzzyStart || fuzzyEnd) {
        final w = max(1.0, rect.width);
        final fadeFrac = min(0.28, 16.0 / w);
        final colors = <Color>[
          fuzzyStart ? barColor.withValues(alpha: 0.08) : barColor,
          barColor,
          barColor,
          fuzzyEnd ? barColor.withValues(alpha: 0.08) : barColor,
        ];
        final stops = <double>[
          0.0,
          fuzzyStart ? fadeFrac : 0.0,
          fuzzyEnd ? 1.0 - fadeFrac : 1.0,
          1.0,
        ];
        final paint = Paint()
          ..shader = LinearGradient(
            colors: colors,
            stops: stops,
          ).createShader(rect);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          paint,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = barColor,
        );
      }

      // Offene Endkante markieren
      if (ongoing) {
        canvas.drawLine(
          Offset(x2, rect.top),
          Offset(x2, rect.bottom),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.75)
            ..strokeWidth = 1.6,
        );
      }

      // Badge wenn Sicherheitsverhalten in dieser Phase aktiv waren
      if (phase.activeSafetyBehaviorIds.isNotEmpty && rect.width >= 16) {
        final badgeCx = (rect.left + rect.right) / 2;
        final badgeCy = rect.top - 5;
        final count = phase.activeSafetyBehaviorIds.length;
        final pill = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(badgeCx, badgeCy),
            width: 22,
            height: 12,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          pill,
          Paint()..color = const Color(0xFFD4A359).withValues(alpha: 0.92),
        );
        _drawSingleLineText(
          canvas,
          'S$count',
          Offset(badgeCx - 10, badgeCy - 5.5),
          20,
          const TextStyle(
            color: Color(0xFF1A1407),
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
          ),
          align: TextAlign.center,
        );
      }
    }

    // Expositions-Übungsmarker im Detail-Zoom
    if (item.exposureSessionMarkers.isNotEmpty) {
      final markerY = row.bottom - 7.0;
      for (final m in item.exposureSessionMarkers) {
        final mx = _dayToX(m.day.toDouble() + 0.5, timelineWidth);
        if (m.status == SessionStatus.aborted) {
          canvas.drawCircle(
            Offset(mx, markerY),
            3.2,
            Paint()
              ..color = theme.colorScheme.error
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        } else {
          canvas.drawCircle(
            Offset(mx, markerY),
            3.2,
            Paint()..color = Colors.white.withValues(alpha: 0.9),
          );
        }
      }
    }
  }

  double _severityHeight(Severity s) {
    switch (s) {
      case Severity.dormant:
        return 4.0;
      case Severity.background:
        return 10.0;
      case Severity.moderate:
        return 16.0;
      case Severity.acute:
        return 22.0;
    }
  }

  double _severityAlpha(Severity s) {
    switch (s) {
      case Severity.dormant:
        return 0.28;
      case Severity.background:
        return 0.45;
      case Severity.moderate:
        return 0.72;
      case Severity.acute:
        return 0.96;
    }
  }

  void _drawDashedVerticalLine(
    Canvas canvas,
    double x,
    double y1,
    double y2,
    Paint paint,
  ) {
    const dash = 4.0;
    const gap = 4.0;
    double y = y1;
    while (y < y2) {
      canvas.drawLine(Offset(x, y), Offset(x, min(y + dash, y2)), paint);
      y += dash + gap;
    }
  }

  void _drawSingleLineText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    TextStyle style, {
    TextAlign align = TextAlign.left,
  }) {
    if (maxWidth <= 2) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: maxWidth, maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.packedContext != packedContext ||
        oldDelegate.startDay != startDay ||
        oldDelegate.spanDays != spanDays ||
        oldDelegate.todayDay != todayDay ||
        oldDelegate.verticalScrollOffset != verticalScrollOffset ||
        oldDelegate.theme != theme;
  }
}
