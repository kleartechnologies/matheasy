import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A single learner testimonial: a real quote attributed to a real person, with
/// their photo. Purely a data holder so the copy lives in one reviewable place.
class Testimonial {
  const Testimonial({
    required this.quote,
    required this.name,
    required this.detail,
    required this.image,
  });

  /// The verbatim quote (never paraphrased or invented).
  final String quote;

  /// The learner's display name / attribution.
  final String name;

  /// A short, real context line — e.g. the subject or level they study.
  final String detail;

  /// Bundled portrait asset path (see `pubspec.yaml`).
  final String image;
}

/// Social proof on the paywall: a swipeable carousel of learner testimonials,
/// each a photo + quote + attribution, on the always-dark premium surface.
///
/// Renders on [AppColors.premiumDeep], so it uses light-on-dark tokens directly
/// rather than `context.colors`. Motion is user-driven only (swipe) — there is
/// no auto-advance — so it stays calm and reduced-motion friendly.
///
/// The quotes below are REAL learner feedback. Apple Review Guideline 2.3.1
/// (and Google Play policy) prohibit fabricated reviews, so only ever edit them
/// to other genuine, attributable quotes; the accompanying photos are
/// representative learner portraits. Passing an empty [testimonials] list hides
/// the section entirely (see [build]).
class PaywallTestimonials extends StatefulWidget {
  const PaywallTestimonials({
    super.key,
    this.testimonials = _defaultTestimonials,
  });

  final List<Testimonial> testimonials;

  static const List<Testimonial> _defaultTestimonials = [
    Testimonial(
      quote:
          'I finally understand why the answer works, not just what the answer '
          'is. The visual explanations make math so much easier to follow.',
      name: 'Sarah',
      detail: 'Secondary School Student',
      image: 'assets/testimonials/sarah_l.png',
    ),
    Testimonial(
      quote:
          'I used Matheasy to revise for my Add Maths exam and finally '
          'understood differentiation. The visual learning feature is amazing.',
      name: 'Muhammad',
      detail: 'TestFlight User',
      // Representative learner portrait.
      image: 'assets/testimonials/vikram.png',
    ),
    Testimonial(
      quote:
          'Practice mode adapts to my weak topics, so I’m actually improving '
          'instead of solving random questions. This has become my daily study '
          'app.',
      name: 'Lisa',
      detail: 'College Student',
      image: 'assets/testimonials/lisa_m.png',
    ),
  ];

  @override
  State<PaywallTestimonials> createState() => _PaywallTestimonialsState();
}

class _PaywallTestimonialsState extends State<PaywallTestimonials> {
  // A slightly < 1 viewport so the neighbouring cards peek — a small, static
  // cue that the row is swipeable, without any ambient motion.
  final PageController _controller = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.testimonials;
    // No real testimonials → render nothing (never ship an empty/fake carousel).
    if (items.isEmpty) return const SizedBox.shrink();

    // The carousel cells are a fixed height (a PageView needs bounded height and
    // can't reflow), so cap text scaling here — as the tab bar does — to keep a
    // long quote from overflowing the card, while still honouring moderate
    // enlargement. The rest of the paywall keeps the user's full text scale.
    final mq = MediaQuery.of(context);
    final cappedTextScaler = mq.textScaler.clamp(maxScaleFactor: 1.2);

    return MediaQuery(
      data: mq.copyWith(textScaler: cappedTextScaler),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.l10n.paywallTestimonialsTitle,
              style: AppTypography.label.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            // Sized to fit a 4-line quote + the attribution row at the capped
            // text scale, so the real (multi-sentence) quotes never clip.
            height: 232,
            child: PageView.builder(
              controller: _controller,
              itemCount: items.length,
              padEnds: false,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(
                  right: i == items.length - 1 ? 0 : AppSpacing.md,
                ),
                child: _TestimonialCard(item: items[i]),
              ),
            ),
          ),
          if (items.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _PageDots(count: items.length, active: _page),
          ],
        ],
      ),
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({required this.item});

  final Testimonial item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '"${item.quote}" — ${item.name}, ${item.detail}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: 26,
              color: AppColors.gold.withValues(alpha: 0.8),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Text(
                item.quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _Avatar(image: item.image),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: AppTypography.title.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                      Text(
                        item.detail,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    const double size = 46;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: ClipOval(
        child: Image.asset(
          image,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Portraits frame the face high, so bias the square crop upward.
          alignment: const Alignment(0, -0.3),
          // Keep the card intact if an asset is ever missing/renamed.
          errorBuilder: (context, error, stack) => Container(
            color: Colors.white.withValues(alpha: 0.08),
            alignment: Alignment.center,
            child: Icon(
              Icons.person_rounded,
              size: 24,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.standard,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
