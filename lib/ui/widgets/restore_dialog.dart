import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '../../services/permission_service.dart';
import '../../services/backup_restore_service.dart';
import 'common_dialog_widget.dart';

class RestoreDialog extends StatelessWidget {
  const RestoreDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final restoreDialogController = Get.put(RestoreDialogController());
    final dialog = CommonDialog(
      child: Container(
        height: 300,
        padding:
            const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10.0, top: 10),
                child: Text(
                  "restoreAppData".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SizedBox(
                height: 150,
                child: Center(
                  child: Obx(() {
                    if (restoreDialogController.restoreError.isNotEmpty) {
                      return SingleChildScrollView(
                        child: SelectableText(
                            restoreDialogController.restoreError.value,
                            textAlign: TextAlign.center),
                      );
                    }
                    return restoreDialogController.restoreProgress.toInt() ==
                            restoreDialogController.filesToRestore.toInt()
                        ? Text(
                            "restoreMsg".tr,
                            textAlign: TextAlign.center,
                          )
                        : restoreDialogController.processingFiles.isTrue
                            ? Text("processFiles".tr)
                            : restoreDialogController.restoreRunning.isTrue
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                          "${restoreDialogController.restoreProgress.toInt()}/${restoreDialogController.filesToRestore.toInt()}",
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(
                                        height: 10,
                                      ),
                                      Text("restoring".tr)
                                    ],
                                  )
                                : Text("letsStrart".tr);
                  }),
                ),
              ),
              SizedBox(
                width: double.maxFinite,
                child: Align(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      onTap: () {
                        if (restoreDialogController.restartRequired.value) {
                          if (restoreDialogController.recoveryRequired.value) {
                            exit(0);
                          }
                          GetPlatform.isAndroid
                              ? TerminateRestart.instance.restartApp(
                                  options: const TerminateRestartOptions(
                                    terminate: true,
                                  ),
                                )
                              : exit(0);
                        } else {
                          restoreDialogController.restore();
                        }
                      },
                      child: Obx(
                        () => Visibility(
                          visible: restoreDialogController
                                  .processingFiles.isFalse &&
                              restoreDialogController.restoreRunning.isFalse,
                          replacement: const SizedBox(
                            height: 40,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15.0, vertical: 10),
                            child: Obx(
                              () => Text(
                                restoreDialogController.recoveryRequired.value
                                    ? "closeApp".tr
                                    : restoreDialogController
                                            .restartRequired.value
                                        ? "restartApp".tr
                                        : "restore".tr,
                                style: TextStyle(
                                    color: Theme.of(context).canvasColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
    return Obx(() => PopScope(
          canPop: !restoreDialogController.restartRequired.value &&
              !restoreDialogController.processingFiles.value &&
              !restoreDialogController.restoreRunning.value,
          child: dialog,
        ));
  }
}

class RestoreDialogController extends GetxController {
  final restartRequired = false.obs;
  final recoveryRequired = false.obs;
  final restoreRunning = false.obs;
  final restoreProgress = (-1).obs;
  final filesToRestore = (0).obs;
  final processingFiles = false.obs;
  final restoreError = ''.obs;

  Future<void> restore() async {
    if (processingFiles.value ||
        restoreRunning.value ||
        restartRequired.value) {
      return;
    }
    processingFiles.value = true;
    restoreError.value = '';
    PreparedBackup? prepared;
    try {
      if (!await PermissionService.getExtStoragePermission()) return;
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select backup file',
        type: GetPlatform.isWindows ? FileType.custom : FileType.any,
        allowedExtensions: GetPlatform.isWindows ? ['hmb'] : null,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null || path == '/') return;
      final service = BackupRestoreService(
        databaseDirectory: await Get.find<SettingsScreenController>().dbDir,
        supportDirectory: Get.find<SettingsScreenController>().supportDirPath,
      );
      prepared = await service.prepare(path,
          relocateDownloads: GetPlatform.isWindows || GetPlatform.isLinux);
      filesToRestore.value = prepared.files.length;
      restoreProgress.value = 0;
      await service.apply(prepared,
          closeDatabases: () async {
            restartRequired.value = true;
            processingFiles.value = false;
            restoreRunning.value = true;
            if (Get.isRegistered<AudioHandler>()) {
              await Get.find<AudioHandler>().stop();
            }
            await Get.find<SettingsScreenController>().closeAllDatabases();
          },
          onProgress: (progress) => restoreProgress.value = progress);

      // Picker cache cleanup is optional and cannot invalidate a committed restore.
      try {
        final cache = Directory(
            '${(await getApplicationCacheDirectory()).path}/file_picker');
        if (await cache.exists()) await cache.delete(recursive: true);
      } catch (e) {
        printERROR('Error clearing file picker cache: $e');
      }
    } catch (e) {
      printERROR('Error restoring backup: $e');
      restoreProgress.value = -1;
      filesToRestore.value = 0;
      if (e is BackupRestoreException && e.restartRequired) {
        restartRequired.value = true;
        recoveryRequired.value = e.recoveryRequired;
        restoreError.value = e.recoveryRequired
            ? 'restoreRecoveryRequired'.tr
            : 'restoreRolledBack'.tr;
      } else {
        restoreError.value = 'restorePreparationError'.tr;
      }
    } finally {
      if (prepared != null) {
        try {
          await prepared.dispose();
        } catch (e) {
          printERROR('Error clearing prepared backup: $e');
        }
      }
      processingFiles.value = false;
      restoreRunning.value = false;
    }
  }
}
