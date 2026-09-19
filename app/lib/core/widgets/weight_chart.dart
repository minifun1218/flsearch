import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Weight samples are plotted at their actual dates, rather than evenly
/// spacing irregular weigh-ins and implying a steady rate of change.
class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.points, required this.targetKg});

  final List<({DateTime date, double kg})> points;
  final double targetKg;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '体重趋势，${points.length} 条记录，目标 $targetKg 千克',
    child: SizedBox(
      height: 160,
      width: double.infinity,
      child: CustomPaint(painter: _WeightPainter(points, targetKg)),
    ),
  );
}

class _WeightPainter extends CustomPainter {
  _WeightPainter(this.points, this.targetKg);
  final List<({DateTime date, double kg})> points;
  final double targetKg;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final minimum =
        points.fold(targetKg, (value, point) => math.min(value, point.kg)) -
        0.8;
    final maximum =
        points.fold(targetKg, (value, point) => math.max(value, point.kg)) +
        0.8;
    const left = 36.0;
    const top = 10.0;
    final right = size.width - 4;
    final bottom = size.height - 24;
    final span = math.max(
      1,
      points.last.date.difference(points.first.date).inDays,
    );
    double x(DateTime date) =>
        left +
        (right - left) * date.difference(points.first.date).inDays / span;
    double y(double kg) =>
        bottom - (bottom - top) * (kg - minimum) / (maximum - minimum);

    final grid = Paint()
      ..color = AppColors.lineSoft
      ..strokeWidth = 1;
    for (var index = 0; index <= 2; index++) {
      final kg = minimum + (maximum - minimum) * index / 2;
      final ordinate = y(kg);
      canvas.drawLine(Offset(left, ordinate), Offset(right, ordinate), grid);
      _text(
        canvas,
        kg.toStringAsFixed(1),
        Offset(0, ordinate - 6),
        AppColors.ink4,
      );
    }

    final targetY = y(targetKg);
    final targetPaint = Paint()
      ..color = AppColors.positive.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var offset = left; offset < right; offset += 7) {
      canvas.drawLine(
        Offset(offset, targetY),
        Offset(math.min(offset + 4, right), targetY),
        targetPaint,
      );
    }
    _text(
      canvas,
      '目标 ${targetKg.toStringAsFixed(1)}',
      Offset(right - 67, targetY - 15),
      AppColors.positive,
    );

    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      if (index == 0) {
        path.moveTo(x(point.date), y(point.kg));
      } else {
        path.lineTo(x(point.date), y(point.kg));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.ink
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(
        Offset(x(point.date), y(point.kg)),
        3,
        Paint()..color = AppColors.ink,
      );
    }
    _text(
      canvas,
      '${points.first.date.month}/${points.first.date.day}',
      Offset(left, bottom + 8),
      AppColors.ink3,
    );
    if (points.length > 1) {
      _text(
        canvas,
        '${points.last.date.month}/${points.last.date.day}',
        Offset(right - 31, bottom + 8),
        AppColors.ink3,
      );
    }
  }

  void _text(Canvas canvas, String value, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: AppFonts.text(size: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _WeightPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.targetKg != targetKg;
}
