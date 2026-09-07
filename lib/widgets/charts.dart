// widgets/charts.dart
// Lightweight, dependency-free chart widgets for the manager dashboard.
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A single labeled slice for the donut chart.
class ChartDatum {
  final String label;
  final double value;
  final Color color;
  const ChartDatum({required this.label, required this.value, required this.color});
}

/// 24-hour vertical bar chart with hour labels every 6 hours.
class HourlyBarChart extends StatelessWidget {
  final List<int> values;
  final Color color;
  const HourlyBarChart({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    final int maxVal = values.isEmpty ? 0 : values.reduce(math.max);
    final double safeMax = maxVal == 0 ? 1.0 : maxVal.toDouble();

    return Column(
      children: [
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(values.length, (i) {
              final double h = (values[i] / safeMax) * 110.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (values[i] > 0)
                        Text('${values[i]}', style: const TextStyle(fontSize: 8)),
                      Container(
                        height: math.max(2.0, h),
                        decoration: BoxDecoration(
                          color: values[i] == 0
                              ? Colors.grey.withValues(alpha: 0.15)
                              : color,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(values.length, (i) {
            return Expanded(
              child: Text(
                i % 6 == 0 ? '${i}h' : '',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8, color: Colors.grey[600]),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Simple filled line/area chart for daily revenue values.
class RevenueLineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  const RevenueLineChart({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(values: values, color: color),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _LinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const double pad = 10;
    final double maxVal = values.reduce(math.max);
    final double safeMax = maxVal == 0 ? 1.0 : maxVal;

    double xFor(int i) => values.length == 1
        ? size.width / 2
        : pad + (i * (size.width - pad * 2) / (values.length - 1));
    double yFor(double v) =>
        size.height - pad - (v / safeMax) * (size.height - pad * 2);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPath = Path()..moveTo(xFor(0), size.height - pad);
    for (int i = 0; i < values.length; i++) {
      fillPath.lineTo(xFor(i), yFor(values[i]));
    }
    fillPath.lineTo(xFor(values.length - 1), size.height - pad);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final linePath = Path()..moveTo(xFor(0), yFor(values[0]));
    for (int i = 1; i < values.length; i++) {
      linePath.lineTo(xFor(i), yFor(values[i]));
    }
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = color;
    for (int i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(xFor(i), yFor(values[i])), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Donut chart with a legend.
class DonutChart extends StatelessWidget {
  final List<ChartDatum> data;
  final double size;
  const DonutChart({super.key, required this.data, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _DonutPainter(data)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.map((d) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: d.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(d.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12))),
                    Text('${d.value.toInt()}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<ChartDatum> data;
  _DonutPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final double total = data.fold(0.0, (s, d) => s + d.value);
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    if (total <= 0) {
      final p = Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22;
      canvas.drawCircle(
          Offset(size.width / 2, size.height / 2), size.width / 2 - 12, p);
      return;
    }
    double start = -math.pi / 2;
    for (final d in data) {
      final sweep = (d.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = d.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.data != data;
}
