import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:harmonymusic/utils/get_localization.dart';

class _LibraryController extends LibraryPlaylistsController {
  int refreshes = 0;

  @override
  // Exercise the import flow without starting the production library lifecycle.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> refreshLib() async => refreshes++;
}

void main() {
  late Directory directory;

  setUp(() async {
    Get.testMode = true;
    directory = await Directory.systemTemp.createTemp('harmony-import-ui-');
    Hive.init(directory.path);
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('cancelling file selection keeps the Library page open',
      (tester) async {
    FilePicker.platform = _CancelledFilePicker();
    final controller = Get.put<LibraryPlaylistsController>(_LibraryController())
        as _LibraryController;
    await tester.pumpWidget(GetMaterialApp(
      translations: Languages(),
      locale: const Locale('pt'),
      home: Scaffold(
        body: SortWidget(
          tag: 'import-test',
          screenController: controller,
          isAdditionalOperationRequired: false,
          isImportFeatureRequired: true,
          onSort: (_, __) {},
        ),
      ),
    ));
    await tester.tap(find.byTooltip('Importar Playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selecionar Arquivo'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Importar Playlist'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.isImporting.value, isFalse);
    expect(controller.refreshes, 0);
    expect(directory.listSync(), isEmpty);
  });
}

class _CancelledFilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      null;
}
