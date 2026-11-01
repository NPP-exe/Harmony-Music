import 'package:flutter/material.dart';

import 'home.dart';

class WebExperimentConsentScreen extends StatefulWidget {
  const WebExperimentConsentScreen({super.key});

  @override
  State<WebExperimentConsentScreen> createState() =>
      _WebExperimentConsentScreenState();
}

class _WebExperimentConsentScreenState
    extends State<WebExperimentConsentScreen> {
  final _consentController = TextEditingController();
  bool _saving = false;

  bool get _hasConsented =>
      _consentController.text.trim().toLowerCase() == 'i consent';

  void _continue() {
    if (!_hasConsented || _saving) return;
    setState(() => _saving = true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const Home()),
    );
  }

  @override
  void dispose() {
    _consentController.dispose();
    super.dispose();
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
                            'This is an experimental, unofficial application. Features, playback, availability, and third-party services may change or stop working without notice. Use is at your own discretion.',
                      ),
                      const _NoticeBullet(
                        text:
                            'Preferences, favorites, playlists, search history, and other app data may be stored in this browser using IndexedDB. Browser storage can be lost, cleared, or accessed by anyone with access to this browser profile. Do not rely on it as your only backup.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The app connects to third-party services, including Invidious instances and YouTube, to retrieve music information, images, and audio. These services and your network provider may receive or process your IP address, requests, and technical data under their own privacy policies.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The app does not require a YouTube login. It does not control cookies or data collected by your browser, hosting provider, or third-party services. Review their policies and browser settings separately.',
                      ),
                      const _NoticeBullet(
                        text:
                            'You are responsible for ensuring that your use, access, and any downloads comply with applicable laws, copyright rules, and the terms of each service. Only access or use content you are authorized to use.',
                      ),
                      const _NoticeBullet(
                        text:
                            'Harmony Music is not affiliated with, endorsed by, or an official client of YouTube or Google. Third-party services and content are not controlled or guaranteed by this app.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The app is provided experimentally and may contain errors, interruptions, inaccurate metadata, or data loss. No uninterrupted availability or error-free operation is promised.',
                      ),
                      const _NoticeBullet(
                        text:
                            'This notice is for information only, is not legal advice, and does not waive rights or guarantee immunity from claims or liability. Legal obligations vary by location; seek qualified advice if needed.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _consentController,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Type “I consent” to continue',
                          hintText: 'I consent',
                          helperText:
                              'By entering this phrase, you confirm that you have read and understand the notice above.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed:
                              _hasConsented && !_saving ? _continue : null,
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
