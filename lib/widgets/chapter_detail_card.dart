import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A tappable, expandable card that shows a classical-text chapter
/// reference for one summary point in a chat answer. Collapsed it shows
/// just the chapter title; tapped, it expands to reveal the full
/// astrological explanation behind that point.
///
/// One card per summary bullet — together they form the "references"
/// strip under an AI answer.
class ChapterDetailCard extends StatefulWidget {
  /// Classical text + chapter/topic, e.g.
  /// "Brihat Parashara Hora Shastra — 10th House of Karma".
  final String chapter;

  /// Full reasoning revealed when the card is expanded.
  final String explanation;

  /// 1-based position — shown as a small numbered chip so the user can
  /// match the card to its summary bullet.
  final int pointNumber;

  const ChapterDetailCard({
    super.key,
    required this.chapter,
    required this.explanation,
    required this.pointNumber,
  });

  @override
  State<ChapterDetailCard> createState() => _ChapterDetailCardState();
}

class _ChapterDetailCardState extends State<ChapterDetailCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded
              ? AppColors.purpleAccent.withOpacity(0.45)
              : AppColors.divider.withOpacity(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header — always visible, tappable ────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  // Numbered chip — ties card to its summary bullet.
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.purpleAccent.withOpacity(0.16),
                    ),
                    child: Text(
                      '${widget.pointNumber}',
                      style: const TextStyle(
                        color: AppColors.purpleLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.chapter,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.purpleLight,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── Body — explanation, revealed on expand ────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: AppColors.divider.withOpacity(0.5),
                  ),
                  Text(
                    widget.explanation,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
