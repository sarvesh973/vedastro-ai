import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme/app_theme.dart';

/// Renders a single legal document loaded from `assets/legal/*.md`.
///
/// Implements a minimal subset of markdown sufficient for our policy
/// documents — no extra package dependency:
///
///   * `# `, `## `, `### ` headings
///   * `- ` / `* ` bullet lists
///   * `**bold**` inline
///   * blank-line paragraph breaks
///   * `|` table rows are rendered as plain rows separated by ` • ` so
///     the data-disclosure tables stay readable on phones
///
/// Anything more elaborate would be over-engineering for static legal
/// docs that change a few times a year.
class LegalDocumentScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(widget.assetPath);
      if (!mounted) return;
      setState(() => _content = raw);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load document.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: _content == null
          ? Center(
              child: _error != null
                  ? Text(
                      _error!,
                      style: const TextStyle(color: AppColors.textMuted),
                    )
                  : const CircularProgressIndicator(
                      color: AppColors.purpleLight,
                      strokeWidth: 2.5,
                    ),
            )
          : SafeArea(
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: _renderMarkdown(_content!),
                ),
              ),
            ),
    );
  }

  // ─── Minimal markdown renderer ──────────────────────────────────

  List<Widget> _renderMarkdown(String src) {
    final lines = src.split('\n');
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final joined = paragraph.join(' ').trim();
      paragraph.clear();
      if (joined.isEmpty) return;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _styledRichText(joined,
            const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            )),
      ));
    }

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      // Headings
      if (line.startsWith('### ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            line.substring(4).trim(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
        continue;
      }
      if (line.startsWith('## ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            line.substring(3).trim(),
            style: const TextStyle(
              color: AppColors.purpleLight,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
        continue;
      }
      if (line.startsWith('# ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            line.substring(2).trim(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ));
        continue;
      }

      // Bullet lists
      if (line.startsWith('- ') || line.startsWith('* ')) {
        flushParagraph();
        final content = line.substring(2).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6, right: 8),
                child: Icon(Icons.circle,
                    size: 5, color: AppColors.purpleLight),
              ),
              Expanded(
                child: _styledRichText(
                  content,
                  const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // Table rows -> "cell • cell • cell" line. Skip the "|---|---|"
      // separator row entirely. Good enough for the small data-sharing
      // table in the privacy policy without adding a table widget.
      if (line.startsWith('|')) {
        flushParagraph();
        final cells = line
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        if (cells.every((c) => RegExp(r'^[-: ]+$').hasMatch(c))) continue;
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: _styledRichText(
            cells.join(' • '),
            const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ));
        continue;
      }

      paragraph.add(line.trim());
    }
    flushParagraph();
    return widgets;
  }

  /// Tiny `**bold**` parser. Doesn't try to be perfect — if the source
  /// has something exotic the worst case is the asterisks render as-is.
  Widget _styledRichText(String src, TextStyle base) {
    final spans = <InlineSpan>[];
    final boldStyle = base.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    int i = 0;
    while (i < src.length) {
      final next = src.indexOf('**', i);
      if (next < 0) {
        spans.add(TextSpan(text: src.substring(i)));
        break;
      }
      if (next > i) spans.add(TextSpan(text: src.substring(i, next)));
      final close = src.indexOf('**', next + 2);
      if (close < 0) {
        // Unterminated bold — treat the rest as plain text.
        spans.add(TextSpan(text: src.substring(next)));
        break;
      }
      spans.add(TextSpan(
        text: src.substring(next + 2, close),
        style: boldStyle,
      ));
      i = close + 2;
    }
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}
