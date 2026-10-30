import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import '/services/piped_service.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/music_service.dart';
import '/ui/home.dart';
import '/ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/system_tray.dart';
import 'utils/update_check_flag_file.dart';
import 'services/backup_restore_service.dart';
import 'services/backup_restore_journal.dart';
import 'ui/widgets/backup_recovery_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startApplication();
}

Future<void> _startApplication() async {
  try {
    await initHive();
  } on BackupRecoveryException catch (error) {
    debugPrint(error.toString());
    runApp(BackupRecoveryScreen(
        error: error,
        onRetry: _startApplication,
        onQuarantine: () async {
          await (await _backupRestoreService()).quarantinePending();
          await _startApplication();
        }));
    return;
  }
  _setAppInitPrefs();
  startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (!GetPlatform.isWeb) {
    TerminateRestart.instance.initialize();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if (!GetPlatform.isDesktop && !GetPlatform.isWeb) {
      Get.put(AppLinksController());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return GetMaterialApp(
      title: 'Harmony Music',
      home: const Home(),
      debugShowCheckedModeBanner: false,
      translations: Languages(),
      locale: Locale(
        Hive.box("AppPrefs").get('currentAppLanguageCode') ?? "en",
      ),
      fallbackLocale: const Locale("en"),
      builder: (context, child) {
        final mQuery = MediaQuery.of(context);
        final scale = mQuery.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.1,
        );
        return Stack(
          children: [
            GetX<ThemeController>(
              builder: (controller) {
                final theme = controller.themedata.value ?? ThemeData.dark();
                return MediaQuery(
                  data: mQuery.copyWith(textScaler: scale),
                  child: AnimatedTheme(
                    duration: const Duration(milliseconds: 700),
                    data: theme,
                    child: child!,
                  ),
                );
              },
            ),
            GestureDetector(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  color: Colors.transparent,
                  height: mQuery.padding.bottom,
                  width: mQuery.size.width,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> startApplicationServices() async {
  Get.lazyPut(() => PipedServices(), fenix: true);
  Get.lazyPut(() => MusicServices(), fenix: true);
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
  Get.lazyPut(() => HomeScreenController(), fenix: true);
  Get.lazyPut(() => LibrarySongsController(), fenix: true);
  Get.lazyPut(() => LibraryPlaylistsController(), fenix: true);
  Get.lazyPut(() => LibraryAlbumsController(), fenix: true);
  Get.lazyPut(() => LibraryArtistsController(), fenix: true);
  Get.lazyPut(() => SettingsScreenController(), fenix: true);
  Get.lazyPut(() => Downloader(), fenix: true);
  if (GetPlatform.isDesktop) {
    Get.lazyPut(() => SearchScreenController(), fenix: true);
    Get.put(DesktopSystemTray());
  }
}

Future<void> initHive() async {
  if (GetPlatform.isWeb) {
    await Hive.initFlutter();
  } else {
    final restore = await _backupRestoreService();
    await restore.recoverPending();
    Hive.init(restore.databaseDirectory);
  }
  await Hive.openBox("SongsCache");
  await Hive.openBox("SongDownloads");
  await Hive.openBox('SongsUrlCache');
  await Hive.openBox("AppPrefs");
}

Future<BackupRestoreService> _backupRestoreService() async {
  final support = (await getApplicationSupportDirectory()).path;
  final database = GetPlatform.isDesktop
      ? "$support/db"
      : (await getApplicationDocumentsDirectory()).path;
  return BackupRestoreService(
      databaseDirectory: database, supportDirectory: support);
}

void _setAppInitPrefs() {
  final appPrefs = Hive.box("AppPrefs");
  final defaults = <String, dynamic>{
    'themeModeType': 2,
    'cacheSongs': false,
    'skipSilenceEnabled': false,
    'streamingQuality': 1,
    'themePrimaryColor': 4278199603,
    'discoverContentType': 'QP',
    'newVersionVisibility': updateCheckFlag,
    'cacheHomeScreenData': true,
    'noOfHomeScreenContent': 3,
    'isBottomNavBarEnabled': false,
    'isTransitionAnimationDisabled': false,
    'loudnessNormalizationEnabled': false,
    'autoOpenPlayer': true,
    'restrorePlaybackSession': false,
    'backgroundPlayEnabled': true,
    'keepScreenAwake': false,
    'playerUi': 0,
    'piped': {'isLoggedIn': false, 'token': '', 'instApiUrl': ''},
  };
  for (final entry in defaults.entries) {
    if (!appPrefs.containsKey(entry.key)) {
      appPrefs.put(entry.key, entry.value);
    }
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
