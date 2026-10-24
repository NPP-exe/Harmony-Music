import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '/native_bindings/android_sdk.dart' as android_sdk;
import '../utils/helper.dart';

class PermissionService {
  static Future<bool> getExtStoragePermission() async {
    if (GetPlatform.isDesktop || GetPlatform.isWeb) {
      return true;
    }
    int sdk = 0;
    try {
      sdk = android_sdk.getSDKInt();
    } catch (e) {
      printERROR("getSDKInt error: $e");
    }

    if (sdk >= 33) {
      if (await Permission.audio.isGranted ||
          await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;

      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      if (audioStatus.isPermanentlyDenied || manageStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return await Permission.audio.isGranted ||
          await Permission.manageExternalStorage.isGranted;
    } else if (sdk >= 30) {
      if (await Permission.manageExternalStorage.isGranted ||
          await Permission.storage.isGranted) {
        return true;
      }
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      if (manageStatus.isPermanentlyDenied ||
          storageStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return await Permission.manageExternalStorage.isGranted ||
          await Permission.storage.isGranted;
    } else {
      var status = await Permission.storage.status;
      if (status.isDenied) {
        await [
          Permission.storage,
          Permission.accessMediaLocation,
          Permission.mediaLibrary,
        ].request();
      }

      if (await Permission.storage.isPermanentlyDenied) {
        await openAppSettings();
      }

      return (await Permission.storage.status).isGranted;
    }
  }
}
