import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Chart colours (a validated colour-blind-safe pair + neutrals).
class ChartColors {
  static const primary = Color(0xFF2A78D6); // this month / income
  static const secondary = Color(0xFFEB6834); // spending
  static const soft = Color(0xFF86B6EF); // de-emphasised bars
  static const previous = Color(0xFF8A8F9C); // last month
  static const grid = Color(0xFFE3E7EF);
}

/// 1250 -> "1.3k", 900 -> "900".
String shortAmount(double v) {
  if (v.abs() >= 1000) {
    final k = v / 1000;
    return '${k.toStringAsFixed(k == k.roundToDouble() ? 0 : 1)}k';
  }
  return v.toStringAsFixed(0);
}

/// Rounds a maximum up to 1/2/5 x 10^n so the grid labels stay tidy.
double _niceMax(double v) {
  if (v <= 0) return 100;
  final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final f = v / exp;
  final nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
  return nf * exp;
}

enum _Anchor { left, center, right }

void _text(Canvas canvas, String s, double x, double y,
    {_Anchor anchor = _Anchor.center,
    bool bold = false,
    Color color = AppColors.textSecondary,
    double size = 10}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontSize: size,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = switch (anchor) {
    _Anchor.left => x,
    _Anchor.center => x - tp.width / 2,
    _Anchor.right => x - tp.width,
  };
  tp.paint(canvas, Offset(dx, y - tp.height / 2)); // y = vertical centre
}

class _Plot {
  final double left, right, top, bottom;
  const _Plot(this.left, this.right, this.top, this.bottom);
  double get width => right - left;
  double get height => bottom - top;
}

void _grid(Canvas canvas, _Plot p, double maxV) {
  final line = Paint()
    ..color = ChartColors.grid
    ..strokeWidth = 1;
  for (final f in const [0.0, 0.5, 1.0]) {
    final y = p.bottom - f * p.height;
    canvas.drawLine(Offset(p.left, y), Offset(p.right, y), line);
    _text(canvas, shortAmount(maxV * f), p.left - 6, y,
        anchor: _Anchor.right);
  }
}

void _bar(Canvas canvas, double x, double w, double bottom, double h, Paint p) {
  if (h <= 0) return;
  final r = math.min(3.0, h);
  canvas.drawRRect(
    RRect.fromLTRBAndCorners(x, bottom - h, x + w, bottom,
        topLeft: Radius.circular(r), topRight: Radius.circular(r)),
    p,
  );
}

void _dashedHLine(Canvas canvas, double x1, double x2, double y, Paint p) {
  const dash = 4.0, gap = 3.0;
  var x = x1;
  while (x < x2) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, x2), y), p);
    x += dash + gap;
  }
}

// ─── 1. Daily spending histogram ───────────────────────────────────────────

class DailySpendChart extends StatelessWidget {
  /// Spending per day; index 0 = day 1. Length = days in the month.
  final List<double> daily;

  /// Last day that has happened (today for the current month).
  final int lastDay;

  const DailySpendChart({super.key, required this.daily, required this.lastDay});

  @override
  Widget build(BuildContext context) {
    final upTo = lastDay.clamp(1, daily.length);
    final peak = daily.take(upTo).fold(0.0, math.max);
    final total = daily.take(upTo).fold(0.0, (a, b) => a + b);
    return Semantics(
      label: 'Daily spending chart. Biggest day EGP ${peak.toStringAsFixed(0)}, '
          'average EGP ${(total / upTo).toStringAsFixed(0)} per day.',
      child: SizedBox(
        width: double.infinity,
        height: 190,
        child: CustomPaint(painter: _DailyPainter(daily, upTo)),
      ),
    );
  }
}

class _DailyPainter extends CustomPainter {
  final List<double> daily;
  final int lastDay;
  _DailyPainter(this.daily, this.lastDay);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _Plot(36, size.width - 4, 16, size.height - 22);
    final days = daily.length;
    var peak = 0.0;
    var peakIdx = -1;
    var total = 0.0;
    for (var i = 0; i < lastDay; i++) {
      total += daily[i];
      if (daily[i] > peak) {
        peak = daily[i];
        peakIdx = i;
      }
    }
    final maxV = _niceMax(peak);
    _grid(canvas, plot, maxV);

    final slot = plot.width / days;
    final bw = math.min(slot * 0.62, 14.0);
    final base = Paint()..color = ChartColors.soft;
    final hi = Paint()..color = ChartColors.primary;
    for (var i = 0; i < lastDay; i++) {
      final v = daily[i];
      if (v <= 0) continue;
      final h = v / maxV * plot.height;
      final x = plot.left + i * slot + (slot - bw) / 2;
      _bar(canvas, x, bw, plot.bottom, h, i == peakIdx ? hi : base);
    }

    if (peakIdx >= 0) {
      final x = plot.left + peakIdx * slot + slot / 2;
      _text(canvas, shortAmount(peak), x, plot.bottom - peak / maxV * plot.height - 9,
          bold: true, color: AppColors.textPrimary, size: 11);
    }

    if (lastDay > 0 && total > 0) {
      final avg = total / lastDay;
      final y = plot.bottom - avg / maxV * plot.height;
      _dashedHLine(
        canvas, plot.left, plot.right, y,
        Paint()
          ..color = AppColors.textSecondary
          ..strokeWidth = 1.5,
      );
      _text(canvas, 'Avg ${shortAmount(avg)}', plot.right, y - 8,
          anchor: _Anchor.right);
    }

    for (final d in const [1, 5, 10, 15, 20, 25, 30]) {
      if (d > days) continue;
      _text(canvas, '$d', plot.left + (d - 1) * slot + slot / 2, plot.bottom + 13);
    }
  }

  @override
  bool shouldRepaint(covariant _DailyPainter old) => true;
}

// ─── 2. Pace: cumulative spending, this month vs last month ────────────────

class PaceChart extends StatelessWidget {
  /// Running total per day for the selected month (index 0 = day 1), only up
  /// to the last day that has happened.
  final List<double> current;

  /// Running total for the previous month, full length (may be empty).
  final List<double> previous;

  /// Days in the selected month (x-axis length is max of both months).
  final int monthDays;

  final String currentLabel;
  final String previousLabel;

  const PaceChart({
    super.key,
    required this.current,
    required this.previous,
    required this.monthDays,
    required this.currentLabel,
    required this.previousLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = current.isEmpty ? 0 : current.last;
    final p = previous.isEmpty ? 0 : previous.last;
    return Semantics(
      label: 'Cumulative spending. $currentLabel EGP ${c.toStringAsFixed(0)} so far, '
          '$previousLabel EGP ${p.toStringAsFixed(0)} in total.',
      child: SizedBox(
        width: double.infinity,
        height: 160,
        child: CustomPaint(
          painter: _PacePainter(current, previous, monthDays, currentLabel, previousLabel),
        ),
      ),
    );
  }
}

class _PacePainter extends CustomPainter {
  final List<double> current;
  final List<double> previous;
  final int monthDays;
  final String currentLabel;
  final String previousLabel;
  _PacePainter(this.current, this.previous, this.monthDays, this.currentLabel,
      this.previousLabel);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _Plot(36, size.width - 6, 14, size.height - 22);
    final xDays = math.max(monthDays, previous.length);
    final maxData = math.max(current.isEmpty ? 0.0 : current.last,
        previous.isEmpty ? 0.0 : previous.last);
    final maxV = _niceMax(maxData);
    _grid(canvas, plot, maxV);

    double x(int day) =>
        plot.left + (xDays <= 1 ? 0 : (day - 1) / (xDays - 1) * plot.width);
    double y(double v) => plot.bottom - v / maxV * plot.height;

    Path line(List<double> v) {
      final path = Path();
      for (var i = 0; i < v.length; i++) {
        final pt = Offset(x(i + 1), y(v[i]));
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      return path;
    }

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (previous.length > 1) {
      canvas.drawPath(line(previous), stroke(ChartColors.previous));
    }
    if (current.length > 1) {
      canvas.drawPath(line(current), stroke(ChartColors.primary));
    }

    if (current.isNotEmpty) {
      final c = Offset(x(current.length), y(current.last));
      canvas.drawCircle(c, 6, Paint()..color = Colors.white);
      canvas.drawCircle(c, 4, Paint()..color = ChartColors.primary);
      _text(canvas, '$currentLabel ${shortAmount(current.last)}',
          math.min(c.dx + 4, plot.right), c.dy - 12,
          anchor: _Anchor.right,
          bold: true,
          color: AppColors.textPrimary,
          size: 11);
    }
    if (previous.isNotEmpty) {
      _text(canvas, '$previousLabel ${shortAmount(previous.last)}', plot.right,
          y(previous.last) + 13,
          anchor: _Anchor.right, size: 11);
    }

    for (final d in const [1, 10, 20, 30]) {
      if (d > xDays) continue;
      _text(canvas, '$d', x(d), plot.bottom + 13);
    }
  }

  @override
  bool shouldRepaint(covariant _PacePainter old) => true;
}

// ─── 3. Income vs spending, last N months ──────────────────────────────────

class MonthTotals {
  final String label;
  final double income;
  final double expense;
  const MonthTotals(this.label, this.income, this.expense);
}

class MonthlyBarsChart extends StatelessWidget {
  final List<MonthTotals> months;
  const MonthlyBarsChart({super.key, required this.months});

  @override
  Widget build(BuildContext context) {
    final last = months.isEmpty ? null : months.last;
    return Semantics(
      label: 'Income versus spending by month.'
          '${last == null ? '' : ' ${last.label}: income EGP ${last.income.toStringAsFixed(0)}, spending EGP ${last.expense.toStringAsFixed(0)}.'}',
      child: SizedBox(
        width: double.infinity,
        height: 170,
        child: CustomPaint(painter: _MonthlyPainter(months)),
      ),
    );
  }
}

class _MonthlyPainter extends CustomPainter {
  final List<MonthTotals> months;
  _MonthlyPainter(this.months);

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    final plot = _Plot(36, size.width - 4, 18, size.height - 22);
    var peak = 0.0;
    for (final m in months) {
      peak = math.max(peak, math.max(m.income, m.expense));
    }
    final maxV = _niceMax(peak);
    _grid(canvas, plot, maxV);

    final slot = plot.width / months.length;
    final bw = math.min(slot * 0.3, 14.0);
    const gap = 3.0;
    final inc = Paint()..color = ChartColors.primary;
    final exp = Paint()..color = ChartColors.secondary;

    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      final gx = plot.left + i * slot + (slot - (2 * bw + gap)) / 2;
      final hi = m.income / maxV * plot.height;
      final he = m.expense / maxV * plot.height;
      _bar(canvas, gx, bw, plot.bottom, hi, inc);
      _bar(canvas, gx + bw + gap, bw, plot.bottom, he, exp);
      if (i == months.length - 1) {
        if (m.income > 0) {
          _text(canvas, shortAmount(m.income), gx + bw / 2,
              plot.bottom - hi - 8, bold: true, color: AppColors.textPrimary);
        }
        if (m.expense > 0) {
          _text(canvas, shortAmount(m.expense), gx + bw + gap + bw / 2,
              plot.bottom - he - 8, bold: true, color: AppColors.textPrimary);
        }
      }
      _text(canvas, m.label, plot.left + i * slot + slot / 2, plot.bottom + 13);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyPainter old) => true;
}
