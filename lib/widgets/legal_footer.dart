import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Legal-entity footer. Payment gateways (Cashfree / Razorpay) require the
/// registered company name to be clearly displayed in the app — this shows
/// the operating brand (Moksha) and the legal entity (Yashvasin Technologies
/// Private Limited), matching the website footer + incorporation documents.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Column(
        children: [
          const Text(
            'Moksha — a product of Yashvasin Technologies Private Limited',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 11.5, height: 1.45),
          ),
          const SizedBox(height: 3),
          Text(
            '© $year Yashvasin Technologies Private Limited. All Rights Reserved.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }
}
