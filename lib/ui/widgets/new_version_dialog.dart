import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/app_constants.dart';
import '../screens/Home/home_screen_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'common_dialog_widget.dart';

class NewVersionDialog extends StatelessWidget {
  const NewVersionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsCon = Get.find<SettingsScreenController>();
    return CommonDialog(
      child: Container(
        height: 350,
        padding: const EdgeInsets.only(top: 30, bottom: 20, left: 20, right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "newVersionAvailable".tr,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Obx(() {
              final cur = settingsCon.currentVersion;
              final latest = settingsCon.latestVersion.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  latest.isNotEmpty ? "$cur  ➔  $latest" : cur,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SizedBox.square(
                dimension: 80,
                child: FittedBox(
                  child: FloatingActionButton(
                    tooltip: "Download Update",
                    onPressed: () {
                      final targetUrl = settingsCon.releaseUrl.value.isNotEmpty
                          ? settingsCon.releaseUrl.value
                          : appReleasesUrl;
                      launchUrl(
                        Uri.parse(targetUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: const Icon(
                      Icons.download,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GetX<HomeScreenController>(builder: (controller) {
                    return Checkbox(
                        value: controller.showVersionDialog.isFalse,
                        onChanged: (val) {
                          controller.onChangeVersionVisibility(val ?? false);
                        },
                        shape: const CircleBorder());
                  }),
                  Text("dontShowInfoAgain".tr)
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
                decoration: BoxDecoration(
                    color: Theme.of(context).textTheme.titleLarge!.color,
                    borderRadius: BorderRadius.circular(10)),
                child: InkWell(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15.0, vertical: 10),
                    child: Text("dismiss".tr,
                        style: TextStyle(color: Theme.of(context).canvasColor)),
                  ),
                  onTap: () => Navigator.of(context).pop(),
                ))
          ],
        ),
      ),
    );
  }
}

