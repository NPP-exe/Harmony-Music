
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
  bool _continuing = false;

  bool get _hasUnderstood =>
      _consentController.text.trim().toLowerCase() == 'i understand';

  void _continue() {
    if (!_hasUnderstood || _continuing) return;

    setState(() => _continuing = true);

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
                        'Experimental Software',
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
                            'This is an independent, unofficial experimental software project provided for personal use and evaluation.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The application may use third-party services, including Invidious and YouTube, to retrieve media and related information. These services operate independently and are not controlled by this project.',
                      ),
                      const _NoticeBullet(
                        text:
                            'Application preferences and other settings may be stored locally in your browser.',
                      ),
                      const _NoticeBullet(
                        text:
                            'All third-party content remains subject to the rights of its respective owners. Users are responsible for complying with applicable laws and service terms.',
                      ),
                      const _NoticeBullet(
                        text:
                            'This project is not affiliated with, endorsed by, or officially associated with YouTube, Google, or Invidious.',
                      ),
                      const _NoticeBullet(
                        text:
                            'The software is experimental and provided as-is, to the extent permitted by applicable law. Nothing in this notice excludes liability or statutory rights where exclusion is prohibited.',
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _consentController,
                        enabled: !_continuing,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Type "I understand" to continue',
                          hintText: 'I understand',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _hasUnderstood && !_continuing
                              ? _continue
                              : null,
                          child: Text(
                            _continuing ? 'Continuing…' : 'Continue',
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
