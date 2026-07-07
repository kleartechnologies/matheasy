import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// A placeholder for the live camera preview — a dark, subtly-lit scene with a
/// faint "problem on paper". Stage 5 replaces this with the real camera texture
/// behind the same overlay chrome.
class CameraViewport extends StatelessWidget {
  const CameraViewport({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.1,
          colors: [
            Color(0xFF262D49),
            Color(0xFF141930),
            AppColors.scannerBackground,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Faint problem "on paper" within the scene.
          Align(
            alignment: const Alignment(0, -0.05),
            child: Transform.rotate(
              angle: -0.05,
              child: const Text(
                '3x − 7 = 8',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: Color(0x52E9EFFF),
                ),
              ),
            ),
          ),
          // Edge vignette.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0x00000000), Color(0x8C000000)],
                stops: [0.6, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
