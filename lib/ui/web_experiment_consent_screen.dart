import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'home.dart';

class WebExperimentConsentScreen extends StatefulWidget {
  const WebExperimentConsentScreen({super.key});

  @override
  State<WebExperimentConsentScreen> createState() =>
      _WebExperimentConsentScreenState();
}

class _WebExperimentConsentScreenState
    extends State<WebExperimentConsentScreen> {
  bool _acknowledged = false;
  bool _saving = false;

  Future<void> _continue() async {
    if (!_acknowledged || _saving) return;
    setState(() => _saving = true);
    try {
      await Hive.box('AppPrefs').put('webExperimentConsentVersion', 1);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const Home()),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not save web experiment consent: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save your choice in browser storage. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Experimental web app',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Please review this information before continuing:',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      const _NoticeBullet(
                        text:
                            'This is experimental software. Features, playback, and third-party services may be unavailable or change without notice.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The app stores preferences, playlists, favorites, and recent playback data in this browser using local storage (IndexedDB). Clearing this site’s browser data may remove it.',
                      ),
                      const _NoticeBullet(
                        text:
                            'Music information, images, and audio are requested from third-party services, including Invidious instances that relay YouTube content. Those services may process request data such as your IP address under their own policies.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The app does not require a YouTube login. Your browser and third-party services may use cookies according to their own settings and policies.',
                      ),
                      const _NoticeBullet(
                        text:
                            'You are responsible for using the app in accordance with applicable laws and the terms of services you access. This notice is informational; it does not waive legal rights or guarantee legal protection.',
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _acknowledged,
                        onChanged: _saving
                            ? null
                            : (value) => setState(
                                  () => _acknowledged = value ?? false,
                                ),
                        title: const Text(
                          'I have read and understand this information, and want to continue.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed:
                              _acknowledged && !_saving ? _continue : null,
                          child: Text(
                            _saving ? 'Saving…' : 'Accept and continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBullet extends StatelessWidget {
  const _NoticeBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 12),
            child: Icon(Icons.circle, size: 7),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
