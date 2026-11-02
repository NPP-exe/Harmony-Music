import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/app_constants.dart';
import '../../widgets/new_version_dialog.dart';
import '../../widgets/snackbar.dart';
import 'settings_screen_controller.dart';

/// Reusable Frosted Glass Card specification
Widget frostedGlassCard({
  required Widget child,
  double? height,
  EdgeInsetsGeometry? padding,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        height: height,
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color(0xFF0C131D).withValues(alpha: 0.85),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsScreenController>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Get.back(),
                    tooltip: 'Back',
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: context.isPhone ? 6.0 : 20.0,
                  vertical: 12.0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: AppInfoContent(
                      settingsController: settingsController,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppInfoContent extends StatelessWidget {
  final SettingsScreenController settingsController;

  const AppInfoContent({super.key, required this.settingsController});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 680;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero Branding: Waveform, App Name & Version Pill
            _buildHeroBranding(context),
            const SizedBox(height: 22),

            // 2. Developer Hero Card (Large & Balanced)
            _buildDeveloperHeroCard(context, constraints),
            const SizedBox(height: 22),

            // 3. Bottom Grid Cards (2 columns on wide, stacked on mobile)
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildContributorsCard(context),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildGitHubCard(context),
                        const SizedBox(height: 18),
                        _buildUpdatesCard(context),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildContributorsCard(context),
                  const SizedBox(height: 16),
                  _buildGitHubCard(context),
                  const SizedBox(height: 16),
                  _buildUpdatesCard(context),
                ],
              ),
            const SizedBox(height: 24),

            // 4. Subtle Footer
            Center(
              child: Obx(
                () => Text(
                  "Harmony Music ${settingsController.formattedVersion} • $appGithubUser",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// 1. Hero Branding
  Widget _buildHeroBranding(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing Cyan Audio Waveform with soft glow
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                blurRadius: 36,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/branding_waveform_cyan.png',
            height: isMobile ? 64 : 80,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 14),

        // HARMONY MUSIC Stencil-cut Typography (Rafika Font)
        SizedBox(
          height: isMobile ? 38 : 48,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Image.asset(
              'assets/images/branding_harmony_music.png',
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Ultra-clean Version Tag Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Obx(
            () => Text(
              settingsController.formattedVersion,
              style: TextStyle(
                color: const Color(0xFF00E5FF),
                fontSize: isMobile ? 12.5 : 14.0,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 2. Developer Hero Card (Large & Balanced)
  Widget _buildDeveloperHeroCard(
      BuildContext context, BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;

    if (isMobile) {
      // APK / Mobile: ONE BELOW ANOTHER (Vertical stack, large and centered)
      return frostedGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // "Maintained by NPP" (Large & Centered)
            Image.asset(
              'assets/images/branding_maintained_by_npp.png',
              height: 72.0,
              fit: BoxFit.contain,
              color: Colors.white,
            ),
            const SizedBox(height: 18),
            // "Narayan" signature with multi-layer cyan neon glow (Large & Centered)
            Image.asset(
              'assets/images/branding_signature_cyan_glow.png',
              height: 135.0,
              fit: BoxFit.contain,
            ),
          ],
        ),
      );
    } else {
      // EXE / Desktop: SINGLE ROW (Side by side, large & balanced)
      return frostedGlassCard(
        height: 200.0,
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // LEFT: "Maintained by NPP"
            Expanded(
              flex: 6,
              child: Container(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  'assets/images/branding_maintained_by_npp.png',
                  height: 95.0,
                  fit: BoxFit.contain,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(width: 24.0),

            // RIGHT: "Narayan" signature
            Expanded(
              flex: 6,
              child: Container(
                alignment: Alignment.centerRight,
                child: Image.asset(
                  'assets/images/branding_signature_cyan_glow.png',
                  height: 175.0,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  /// 3A. Contributors Card
  Widget _buildContributorsCard(BuildContext context) {
    return frostedGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icons.people in cyan + "Contributors" in bold white
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.people,
                  color: Color(0xFF00E5FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Contributors",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Bullet 1: "• NPP-exe" + Capsule Pill "(Maintainer)"
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => launchUrl(
              Uri.parse("https://github.com/NPP-exe"),
              mode: LaunchMode.externalApplication,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                children: [
                  const Text(
                    "• ",
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "NPP-exe",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildCapsulePill("(Maintainer)", const Color(0xFF00E5FF)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Bullet 2: "• anandnet" + Capsule Pill "(Original Creator)"
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => launchUrl(
              Uri.parse("https://github.com/anandnet"),
              mode: LaunchMode.externalApplication,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                children: [
                  const Text(
                    "• ",
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "anandnet",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildCapsulePill(
                      "(Original Creator)", const Color(0xFF00E5FF)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Bullet 3: "• Community Contributors & Beta Testers"
          const Row(
            children: [
              Text(
                "• ",
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: Text(
                  "Community Contributors & Beta Testers",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Overlapping Avatar Circles Row
          Padding(
            padding: const EdgeInsets.only(left: 14.0),
            child: SizedBox(
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    child: _buildAvatarCircle(
                      label: "BP",
                      handle: "@BandhanPramanik",
                      color: const Color(0xFF38BDF8),
                      url: "https://github.com/BandhanPramanik",
                    ),
                  ),
                  Positioned(
                    left: 24,
                    child: _buildAvatarCircle(
                      label: "M",
                      handle: "@Meralchen",
                      color: const Color(0xFF34D399),
                      url: "https://github.com/Meralchen",
                    ),
                  ),
                  Positioned(
                    left: 48,
                    child: _buildAvatarCircle(
                      label: "TC",
                      handle: "@theblackcoderbr",
                      color: const Color(0xFFF59E0B),
                      url: "https://github.com/theblackcoderbr",
                    ),
                  ),
                  Positioned(
                    left: 72,
                    child: _buildAvatarCircle(
                      label: "J",
                      handle: "@jaxenisr",
                      color: const Color(0xFFA855F7),
                      url: "https://github.com/jaxenisr",
                    ),
                  ),
                  Positioned(
                    left: 96,
                    child: _buildAvatarCircle(
                      label: "❤",
                      handle: "Community Contributors",
                      color: const Color(0xFFEC4899),
                      url:
                          "https://github.com/NPP-exe/Harmony-Music/graphs/contributors",
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

  /// 3B. GitHub Repository Card
  Widget _buildGitHubCard(BuildContext context) {
    return frostedGlassCard(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => launchUrl(
            Uri.parse(appGithubUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Ionicons.logo_github,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "GitHub Repository",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$appGithubUser / $appGithubRepo • Original by $appOriginalAuthor",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3C. Check for Updates Card
  Widget _buildUpdatesCard(BuildContext context) {
    return frostedGlassCard(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            final info = await settingsController.manualCheckNewVersion();
            if (info.isAvailable) {
              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (context) => const NewVersionDialog(),
                );
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  snackbar(
                    context,
                    "You are on the latest version (${settingsController.formattedVersion})",
                    size: SanckBarSize.MEDIUM,
                  ),
                );
              }
            }
          },
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Check for Updates",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Obx(
                      () => Text(
                        settingsController.isNewVersionAvailable.value
                            ? "New version ${settingsController.latestVersion.value} is available!"
                            : "Harmony Music is up to date",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: settingsController.isNewVersionAvailable.value
                              ? Colors.amber[300]
                              : Colors.white.withValues(alpha: 0.55),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper: Capsule Pill with cyan border and subtle glow
  Widget _buildCapsulePill(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.65),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10.5,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// Helper: Overlapping Avatar Circle
  Widget _buildAvatarCircle({
    required String label,
    required String handle,
    required Color color,
    required String url,
  }) {
    return Tooltip(
      message: handle,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF0E1724),
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
