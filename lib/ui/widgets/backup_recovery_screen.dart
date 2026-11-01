import 'package:flutter/material.dart';

import '../../utils/get_localization.dart';

/// Shown before opening Hive when a pending restore cannot yet be recovered.
class BackupRecoveryScreen extends StatefulWidget {
  const BackupRecoveryScreen(
      {super.key,
      required this.error,
      required this.onRetry,
      required this.onQuarantine,
      this.locale});
  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onQuarantine;
  final Locale? locale;

  @override
  State<BackupRecoveryScreen> createState() => _BackupRecoveryScreenState();
}

class _BackupRecoveryScreenState extends State<BackupRecoveryScreen> {
  bool _running = false;
  Object? _actionError;

  @override
  void didUpdateWidget(covariant BackupRecoveryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error != widget.error) _actionError = null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _running = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final languages = Languages().keys;
    final locale =
        widget.locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    final strings = languages[locale.languageCode] ?? languages['en']!;
    String text(String key) => strings[key] ?? languages['en']![key]!;
    return MaterialApp(
      title: 'Harmony Music',
      home: Builder(
          builder: (context) => Scaffold(
                body: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(text('backupRecoveryTitle'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 16),
                          Text(text('backupRecoveryDescription'),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          SelectableText(
                              (_actionError ?? widget.error).toString()),
                          const SizedBox(height: 24),
                          if (_running) const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed:
                                _running ? null : () => _run(widget.onRetry),
                            child: Text(text('retry')),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _running
                                ? null
                                : () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                            text('backupRecoveryConfirmTitle')),
                                        content: Text(text(
                                            'backupRecoveryConfirmDescription')),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text(text('cancel')),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(
                                                text('backupRecoveryContinue')),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true && mounted) {
                                      await _run(widget.onQuarantine);
                                    }
                                  },
                            child: Text(text('backupRecoveryQuarantine')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
    );
  }
}
