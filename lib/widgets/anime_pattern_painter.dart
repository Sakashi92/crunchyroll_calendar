import 'package:flutter/material.dart';

class AnimePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Zeichne stilisierte "Speed Lines" wie in Anime
    for (int i = 0; i < 8; i++) {
      final startX = size.width * (i / 8);
      final startY = 0.0;
      final endX = size.width * ((i + 2) / 8);
      final endY = size.height;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    // Zeichne einige Kreise (wie Anime-Highlights)
    paint.style = PaintingStyle.fill;
    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.2 + i * 0.15);
      final y = size.height * (0.3 + (i % 2) * 0.4);
      canvas.drawCircle(Offset(x, y), 4 + (i % 3) * 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
