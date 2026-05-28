import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void showErrorSnackBar(
  BuildContext context,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  final details = _buildDetails(error, stackTrace);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        action: details != null
            ? SnackBarAction(
                label: 'Подробнее',
                onPressed: () => _showDetailsDialog(context, message, details),
              )
            : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
}

String? _buildDetails(Object? error, StackTrace? stackTrace) {
  if (error == null) return null;
  final buffer = StringBuffer(error.toString());
  if (stackTrace != null) {
    buffer.writeln('\n--- Stack Trace ---');
    final lines = stackTrace.toString().split('\n').take(12);
    buffer.writeAll(lines, '\n');
  }
  return buffer.toString();
}

void _showDetailsDialog(BuildContext context, String message, String details) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Детали ошибки'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                details,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Копировать'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: details));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Скопировано в буфер'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}
