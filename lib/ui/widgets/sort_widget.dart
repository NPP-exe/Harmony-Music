// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';

import 'additional_operation_dialog.dart';
import 'modified_text_field.dart';

enum OperationMode { arrange, delete, addToPlaylist, none }

enum SortType {
  Name,
  Date,
  Duration,
  RecentlyPlayed,
  AddedOrder,
  Custom,
}

Set<SortType> buildSortTypeSet(
    [bool dateRequired = false,
    bool durationRequired = false,
    bool recentlyPlayedRequired = false]) {
  Set<SortType> requiredSortTypes = {};
  if (dateRequired) {
    requiredSortTypes.add(SortType.Date);
  }
  if (durationRequired) {
    requiredSortTypes.add(SortType.Duration);
  }
  if (recentlyPlayedRequired) {
    requiredSortTypes.add(SortType.RecentlyPlayed);
  }
  return requiredSortTypes;
}

class SortWidget extends StatelessWidget {
  /// Additional operations - Delete Multiple songs, Rearrage offline playlist, Add Multiple songs to playlist
  const SortWidget({
    super.key,
    required this.tag,
    this.itemCountTitle = '',
    this.titleLeftPadding = 18,
    this.isAdditionalOperationRequired = true,
    this.requiredSortTypes = const <SortType>{SortType.Name},
    this.isSearchFeatureRequired = false,
    this.isPlaylistRearrageFeatureRequired = false,
    this.isSongDeletetioFeatureRequired = false,
    required this.screenController,
    this.onSearchStart,
    this.onSearch,
    this.onSearchClose,
    this.itemIcon,
    this.startAdditionalOperation,
    this.selectAll,
    this.performAdditionalOperation,
    this.cancelAdditionalOperation,
    this.isImportFeatureRequired = false,
    this.sortController,
    this.addedOrderTooltip,
    required this.onSort,
  });

  /// unique identifier for each sortwidget
  final String tag;
  final String itemCountTitle;
  final IconData? itemIcon;
  final bool isAdditionalOperationRequired;
  final double titleLeftPadding;
  final Set<SortType> requiredSortTypes;
  final bool isSearchFeatureRequired;
  final bool isSongDeletetioFeatureRequired;
  final bool isPlaylistRearrageFeatureRequired;
  final dynamic screenController;
  final Function(SortWidgetController, OperationMode)? startAdditionalOperation;
  final Function(bool)? selectAll;
  final Function()? performAdditionalOperation;
  final Function()? cancelAdditionalOperation;
  final Function(String?)? onSearchStart;
  final Function(String, String?)? onSearch;
  final Function(String?)? onSearchClose;
  final Function(SortType, bool) onSort;
  final bool isImportFeatureRequired;
  final SortWidgetController? sortController;
  final String? addedOrderTooltip;

  Future<void> _showImportDialog(BuildContext context) async {
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          "importPlaylist".tr,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "importPlaylistDesc".tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              "importLargeFileNote".tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.file_open),
                label: Text("selectFile".tr),
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.secondary,
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text("close".tr),
          ),
        ],
      ),
    );
    if (shouldImport == true && context.mounted) {
      await Get.find<LibraryPlaylistsController>().importPlaylistFromJson(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = sortController ??
        Get.put<SortWidgetController>(SortWidgetController(), tag: tag);
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: SizedBox(
        height: 40,
        child: Obx(
          () => Stack(
            children: [
              if (controller.isSearchingEnabled.isFalse)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: titleLeftPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(itemCountTitle),
                          if (itemIcon != null)
                            Icon(
                              Icons.music_note,
                              size: 15,
                              color: Theme.of(context).colorScheme.secondary,
                            )
                        ],
                      ),
                    ),
                    Obx(
                      () => _customIconButton(
                        isSelected:
                            controller.sortType.value == SortType.Name,
                        icon: Icons.sort_by_alpha,
                        tooltip: "sortByName".tr,
                        onPressed: () {
                          controller.onSortByName(onSort);
                        },
                      ),
                    ),
                    requiredSortTypes.contains(SortType.Date)
                        ? Obx(
                            () => _customIconButton(
                              isSelected:
                                  controller.sortType.value == SortType.Date,
                              icon: Icons.calendar_month,
                              tooltip: "sortByDate".tr,
                              onPressed: () {
                                controller.onSortByDate(onSort);
                              },
                            ),
                          )
                        : const SizedBox.shrink(),
                    requiredSortTypes.contains(SortType.Duration)
                        ? Obx(() => _customIconButton(
                              isSelected: controller.sortType.value ==
                                  SortType.Duration,
                              tooltip: "sortByDuration".tr,
                              icon: Icons.timer,
                              onPressed: () {
                                controller.onSortByDuration(onSort);
                              },
                            ))
                        : const SizedBox.shrink(),
                    if (requiredSortTypes.contains(SortType.AddedOrder))
                      Obx(() => _customIconButton(
                            isSelected: controller.sortType.value ==
                                SortType.AddedOrder,
                            icon: Icons.playlist_add,
                            tooltip: addedOrderTooltip ?? "sortByAddedOrder".tr,
                            onPressed: () =>
                                controller.onSortByAddedOrder(onSort),
                          )),
                    if (requiredSortTypes.contains(SortType.Custom))
                      Obx(() => _customIconButton(
                            isSelected:
                                controller.sortType.value == SortType.Custom,
                            icon: Icons.format_list_numbered,
                            tooltip: "sortByPlaylistOrder".tr,
                            onPressed: () =>
                                controller.onSortByCustomOrder(onSort),
                          )),
                    const Expanded(child: SizedBox()),
                    Obx(
                      () => _customIconButton(
                        icon: controller.isAscending.value
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        tooltip: "sortAscendNDescend".tr,
                        onPressed: () {
                          controller.onAscendNDescend(onSort);
                        },
                      ),
                    ),
                    if (isImportFeatureRequired)
                      _customIconButton(
                        icon: Icons.import_contacts,
                        tooltip: "importPlaylist".tr,
                        onPressed: () => _showImportDialog(context),
                      ),
                    if (isSearchFeatureRequired)
                      _customIconButton(
                        icon: Icons.search,
                        tooltip: "search".tr,
                        onPressed: () {
                          onSearchStart!(tag);
                          controller.toggleSearch();
                        },
                      ),
                    if (isAdditionalOperationRequired)
                      PopupMenuButton(
                        child: const Icon(
                          Icons.more_vert,
                          size: 20,
                        ),
                        // Callback that sets the selected popup menu item.
                        onSelected: (mode) {
                          showDialog(
                              context: context,
                              builder: (context) => AdditionalOperationDialog(
                                    operationMode: mode,
                                    screenController: screenController,
                                    controller: controller,
                                  ));
                
                          controller.setActiveMode(mode);
                          startAdditionalOperation!(controller, mode);
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry>[
                          if (isPlaylistRearrageFeatureRequired)
                            PopupMenuItem(
                              value: OperationMode.arrange,
                              child: Text("reArrangePlaylist".tr),
                            ),
                          if (isSongDeletetioFeatureRequired)
                            PopupMenuItem(
                              value: OperationMode.delete,
                              child: Text("removeMultiple".tr),
                            ),
                          PopupMenuItem(
                            value: OperationMode.addToPlaylist,
                            child: Text("addMultipleSongs".tr),
                          ),
                        ],
                      ),
                    const SizedBox(
                      width: 15,
                    )
                  ],
                ),
              if (controller.isSearchingEnabled.value)
                Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 5, right: 20),
                  // color:
                  //     Theme.of(context).scaffoldBackgroundColor.withAlpha(125),
                  child: ColoredBox(
                    color: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withAlpha(125),
                    child: ModifiedTextField(
                      textAlignVertical: TextAlignVertical.center,
                      autofocus: true,
                      onChanged: (value) {
                        onSearch!(value, tag);
                      },
                      cursorColor:
                          Theme.of(context).textTheme.titleSmall!.color,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.all(8),
                        filled: true,
                        border: const OutlineInputBorder(),
                        hintText: "search".tr,
                        suffixIconColor:
                            Theme.of(context).colorScheme.secondary,
                        suffixIcon: IconButton(
                          splashRadius: 10,
                          iconSize: 20,
                          icon: const Icon(Icons.cancel),
                          onPressed: () {
                            controller.toggleSearch();
                            onSearchClose!(tag);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customIconButton({
    required IconData icon,
    required String tooltip,
    bool? isSelected,
    Function()? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon),
      padding: const EdgeInsets.all(0),
      color: isSelected == null || isSelected == true
          ? Theme.of(Get.context!).textTheme.bodySmall!.color
          : Theme.of(Get.context!).colorScheme.secondary,
      iconSize: 20,
      splashRadius: 20,
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

class SortWidgetController extends GetxController {
  SortWidgetController(
      {SortType initialSortType = SortType.Name, this.isTemporaryPreference})
      : sortType = initialSortType.obs;

  String? preferenceKey;
  final bool Function()? isTemporaryPreference;
  final Rx<SortType> sortType;
  final isAscending = true.obs;
  final isSearchingEnabled = false.obs;
  final isRearraningEnabled = false.obs;
  final isDeletionEnabled = false.obs;
  final isAddtoPlaylistEnabled = false.obs;
  final isAllSelected = false.obs;

  void loadPreference(String key, {SortType defaultSortType = SortType.Name}) {
    preferenceKey = key;
    sortType.value = defaultSortType;
    isAscending.value = true;
    if (!Hive.isBoxOpen('AppPrefs')) return;
    final saved = Hive.box('AppPrefs').get(key);
    if (saved is! Map) return;
    sortType.value = SortType.values.firstWhere(
      (type) => type.name == saved['type'],
      orElse: () => defaultSortType,
    );
    isAscending.value = saved['ascending'] is bool ? saved['ascending'] : true;
  }

  Future<void> setSort(SortType type, bool ascending) async {
    sortType.value = type;
    isAscending.value = ascending;
    final key = preferenceKey;
    final temporary = isTemporaryPreference?.call() ?? false;
    if (key != null && Hive.isBoxOpen('AppPrefs')) {
      final prefs = Hive.box('AppPrefs');
      final updates = <dynamic, dynamic>{
        key: {'type': type.name, 'ascending': ascending},
      };
      final evicted = <String>[];
      if (key.startsWith('playlistSort:')) {
        final recent = List<String>.from(
            prefs.get('temporaryPlaylistSorts', defaultValue: <String>[]));
        recent.remove(key);
        if (temporary) recent.add(key);
        while (recent.length > 100) {
          evicted.add(recent.removeAt(0));
        }
        updates['temporaryPlaylistSorts'] = recent;
      }
      // Hive publishes mutations synchronously. Start the entire update before
      // yielding, so eviction cannot delete a preference saved by a later click.
      await Future.wait([
        prefs.putAll(updates),
        if (evicted.isNotEmpty) prefs.deleteAll(evicted),
      ]);
    }
  }

  void onSortByAddedOrder(Function onSort) {
    sortType.value = SortType.AddedOrder;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByCustomOrder(Function onSort) {
    sortType.value = SortType.Custom;
    onSort(sortType.value, isAscending.value);
  }

  static Future<void> removePlaylistPreference(String id) async {
    if (!Hive.isBoxOpen('AppPrefs')) return;
    final prefs = Hive.box('AppPrefs');
    final key = 'playlistSort:$id';
    final recent = List<String>.from(
        prefs.get('temporaryPlaylistSorts', defaultValue: <String>[]));
    recent.remove(key);
    await Future.wait([
      prefs.put('temporaryPlaylistSorts', recent),
      prefs.delete(key),
    ]);
  }

  void setActiveMode(OperationMode mode) {
    isAddtoPlaylistEnabled.value = OperationMode.addToPlaylist == mode;
    isDeletionEnabled.value = OperationMode.delete == mode;
    isRearraningEnabled.value = OperationMode.arrange == mode;
  }

  void toggleSelectAll(bool val) {
    isAllSelected.value = val;
  }

  void onSortByName(Function onSort) {
    sortType.value = SortType.Name;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByDuration(Function onSort) {
    sortType.value = SortType.Duration;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByDate(Function onSort) {
    sortType.value = SortType.Date;
    onSort(sortType.value, isAscending.value);
  }

  void onAscendNDescend(Function onSort) {
    isAscending.value = !isAscending.value;
    onSort(sortType.value, isAscending.value);
  }

  void toggleSearch() {
    isSearchingEnabled.value = !isSearchingEnabled.value;
  }
}
