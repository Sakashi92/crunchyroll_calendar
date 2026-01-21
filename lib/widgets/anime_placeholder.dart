import 'package:flutter/material.dart';

/// Custom Painter für Anime-ähnliches Muster
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

/// Placeholder Widget für Anime-Cover die noch geladen werden
class AnimePlaceholder extends StatelessWidget {
  final double height;

  const AnimePlaceholder({super.key, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade300,
            Colors.deepOrange.shade400,
            Colors.red.shade400,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Anime-style Pattern
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: CustomPaint(painter: AnimePatternPainter()),
            ),
          ),
          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // TV/Play Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.live_tv,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                // Text
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Cover wird geladen...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
