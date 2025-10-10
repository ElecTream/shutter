import 'package:flutter/material.dart';

class StrikethroughPainter extends CustomPainter {
  final double progress;
  final Color color;
  const StrikethroughPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width * progress, size.height / 2), paint);
  }
  @override
  bool shouldRepaint(covariant StrikethroughPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

