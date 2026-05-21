import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ui_error_log.dart';
import '../theme/app_theme.dart';

/// Admin-only debug screen: lists every Flutter UI error captured this
/// session (widget build failures + framework errors). Reached from
/// Settings → "View UI errors". Each row expands to show the full stack.
class UiErrorLogScreen extends StatefulWidget {
  const UiErrorLogScreen({super.key});

  @override
  State<UiErrorLogScreen> createState() => _UiErrorLogScreenState();
}

class _UiErrorLogScreenState extends State<UiErrorLogScreen> {
  @override
  Widget build(BuildContext context) {
    final entries = UiErrorLog.entries;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('UI Errors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: 'Copy all',
            onPressed: entries.isEmpty
                ? null
                : () {
                    Clipboard.setData(
                        ClipboardData(text: UiErrorLog.formatAll()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Copied to clipboard'),
                        backgroundColor: AppColors.purpleSoft,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Clear',
            onPressed: entries.isEmpty
                ? null
                : () {
                    UiErrorLog.clear();
                    setState(() {});
                  },
          ),
        ],
      ),
      body: entries.isEmpty ? _empty() : _list(entries),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bug_report_outlined,
                size: 56, color: AppColors.textMuted.withOpacity(0.4)),
            const SizedBox(height: 12),
            const Text(
              'No UI errors captured this session.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'When a widget crashes and shows "Something went wrong", the '
              'exception and stack trace appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted.withOpacity(0.7),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<UiErrorEntry> entries) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _ErrorTile(entry: entries[i], index: i + 1),
    );
  }
}

class _ErrorTile extends StatefulWidget {
  final UiErrorEntry entry;
  final int index;
  const _ErrorTile({required this.entry, required this.index});

  @override
  State<_ErrorTile> createState() => _ErrorTileState();
}

class _ErrorTileState extends State<_ErrorTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _open
              ? AppColors.error.withOpacity(0.5)
              : AppColors.divider.withOpacity(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.error.withOpacity(0.16),
                    ),
                    child: Text(
                      '${widget.index}',
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.oneLine,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.library} • ${_clock(e.time)}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more_rounded,
                        color: AppColors.purpleLight, size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: AppColors.divider.withOpacity(0.5),
                  ),
                  SelectableText(
                    '${e.exception}\n\n${e.stack}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy this'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: '${e.exception}\n\n${e.stack}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Copied'),
                            backgroundColor: AppColors.purpleSoft,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _clock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
