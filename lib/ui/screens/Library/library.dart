import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'local_songs_controller.dart';
import 'local_songs_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/modification_list.dart';
import '../../../models/playlist.dart';
import '../../widgets/piped_sync_widget.dart';
import 'library_controller.dart';
import '../../widgets/content_list_widget_item.dart';
import '../../widgets/list_widget.dart';
import '../../widgets/sort_widget.dart';
import '../Settings/settings_screen_controller.dart';

class SongsLibraryWidget extends StatefulWidget {
  const SongsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  State<SongsLibraryWidget> createState() => _SongsLibraryWidgetState();
}

class _SongsLibraryWidgetState extends State<SongsLibraryWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (!Get.isRegistered<LocalSongsController>()) {
      Get.lazyPut<LocalSongsController>(() => LocalSongsController());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = widget.isBottomNavActive
        ? 10.0
        : (context.isLandscape ? 50.0 : 85.0);

    return Padding(
      padding: EdgeInsets.only(
        left: widget.isBottomNavActive ? 15.0 : 5.0,
        right: 10.0,
        top: topPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, right: 10.0, bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.isBottomNavActive) ...[
                  Text(
                    "libSongs".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                ],
                ButtonsTabBar(
                  controller: _tabController,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  backgroundColor:
                      Theme.of(context).textTheme.titleMedium?.color!,
                  unselectedBackgroundColor:
                      Theme.of(context).colorScheme.secondary,
                  borderWidth: 0,
                  borderColor: Colors.transparent,
                  unselectedLabelStyle: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium?.color!,
                    fontWeight: FontWeight.bold,
                  ),
                  labelStyle: TextStyle(
                    color: Theme.of(context).canvasColor,
                    fontWeight: FontWeight.bold,
                  ),
                  tabs: const [
                    Tab(text: "Harmony Songs"),
                    Tab(text: "Local Songs"),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildHarmonySongsTab(context),
                const LocalSongsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarmonySongsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          final libSongsController = Get.find<LibrarySongsController>();
          return SortWidget(
            tag: "LibSongSort",
            screenController: libSongsController,
            itemCountTitle: "${libSongsController.librarySongsList.length}",
            itemIcon: Icons.music_note,
            titleLeftPadding: 9,
            requiredSortTypes: buildSortTypeSet(true, true),
            isSearchFeatureRequired: true,
            isSongDeletetioFeatureRequired: true,
            onSort: (type, ascending) {
              libSongsController.onSort(type, ascending);
            },
            onSearch: libSongsController.onSearch,
            onSearchClose: libSongsController.onSearchClose,
            onSearchStart: libSongsController.onSearchStart,
            startAdditionalOperation:
                libSongsController.startAdditionalOperation,
            selectAll: libSongsController.selectAll,
            performAdditionalOperation:
                libSongsController.performAdditionalOperation,
            cancelAdditionalOperation:
                libSongsController.cancelAdditionalOperation,
          );
        }),
        Expanded(
          child: GetX<LibrarySongsController>(builder: (controller) {
            return controller.librarySongsList.isNotEmpty
                ? (controller.additionalOperationMode.value ==
                        OperationMode.none
                    ? ListWidget(
                        controller.librarySongsList,
                        "library Songs",
                        true,
                        isPlaylistOrAlbum: true,
                        playlist: Playlist(
                            title: "Library Songs",
                            playlistId: "SongsDownloads",
                            thumbnailUrl: "",
                            isCloudPlaylist: false),
                      )
                    : ModificationList(
                        mode: controller.additionalOperationMode.value,
                        screenController: controller,
                      ))
                : Center(
                    child: Text(
                      "noOfflineSong".tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
          }),
        ),
      ],
    );
  }
}

class PlaylistNAlbumLibraryWidget extends StatelessWidget {
  const PlaylistNAlbumLibraryWidget(
      {super.key, this.isAlbumContent = true, this.isBottomNavActive = false});
  final bool isAlbumContent;
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final libralbumCntrller = Get.find<LibraryAlbumsController>();
    final librplstCntrller = Get.find<LibraryPlaylistsController>();
    final settingscrnController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;

    const double itemHeight = 180;
    const double itemWidth = 130;
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                isBottomNavActive
                    ? const SizedBox(
                        height: 10,
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isAlbumContent ? "libAlbums".tr : "libPlaylists".tr,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                (settingscrnController.isBottomNavBarEnabled.isTrue ||
                        isAlbumContent ||
                        settingscrnController.isLinkedWithPiped.isFalse)
                    ? const SizedBox.shrink()
                    : PipedSyncWidget(
                        padding: EdgeInsets.only(right: size.width * .05),
                      )
              ],
            ),
          ),
          Obx(
            () => isAlbumContent
                ? SortWidget(
                    tag: "LibAlbumSort",
                    screenController: libralbumCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${libralbumCntrller.libraryAlbums.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(true),
                    onSort: (type, ascending) {
                      libralbumCntrller.onSort(type, ascending);
                    },
                    onSearch: libralbumCntrller.onSearch,
                    onSearchClose: libralbumCntrller.onSearchClose,
                    onSearchStart: libralbumCntrller.onSearchStart,
                  )
                : SortWidget(
                    tag: "LibPlaylistSort",
                    screenController: librplstCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${librplstCntrller.libraryPlaylists.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(),
                    onSort: (type, ascending) {
                      librplstCntrller.onSort(type, ascending);
                    },
                    onSearch: librplstCntrller.onSearch,
                    onSearchClose: librplstCntrller.onSearchClose,
                    onSearchStart: librplstCntrller.onSearchStart,
                    isImportFeatureRequired: true,
                  ),
          ),
          Expanded(
            child: Obx(
              () => (isAlbumContent
                      ? libralbumCntrller.libraryAlbums.isNotEmpty
                      : librplstCntrller.libraryPlaylists.isNotEmpty)
                  ? LayoutBuilder(builder: (context, constraints) {
                      //Fix for grid in mobile screen
                      final availableWidth = constraints.maxWidth > 300 &&
                              constraints.maxWidth < 394
                          ? 310.0
                          : constraints.maxWidth;
                      int columns = (availableWidth / itemWidth).floor();
                      return SizedBox(
                        width: availableWidth,
                        child: GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              childAspectRatio: (itemWidth / itemHeight),
                            ),
                            controller:
                                ScrollController(keepScrollOffset: false),
                            shrinkWrap: true,
                            scrollDirection: Axis.vertical,
                            padding:
                                const EdgeInsets.only(bottom: 200, top: 10),
                            itemCount: isAlbumContent
                                ? libralbumCntrller.libraryAlbums.length
                                : librplstCntrller.libraryPlaylists.length,
                            itemBuilder: (context, index) => Center(
                                  child: ContentListItem(
                                    content: isAlbumContent
                                        ? libralbumCntrller.libraryAlbums[index]
                                        : librplstCntrller
                                            .libraryPlaylists[index],
                                    isLibraryItem: true,
                                  ),
                                )),
                      );
                    })
                  : Center(
                      child: Text(
                      "noBookmarks".tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    )),
            ),
          )
        ],
      ),
    );
  }
}

class LibraryArtistWidget extends StatelessWidget {
  const LibraryArtistWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final cntrller = Get.find<LibraryArtistsController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5, top: topPadding),
      child: Column(
        children: [
          isBottomNavActive
              ? const SizedBox(
                  height: 10,
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "libArtists".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Obx(
            () => SortWidget(
              tag: "LibArtistSort",
              screenController: cntrller,
              isAdditionalOperationRequired: false,
              isSearchFeatureRequired: true,
              itemCountTitle: "${cntrller.libraryArtists.length} ${"items".tr}",
              onSort: (type, ascending) {
                cntrller.onSort(type, ascending);
              },
              onSearch: cntrller.onSearch,
              onSearchClose: cntrller.onSearchClose,
              onSearchStart: cntrller.onSearchStart,
            ),
          ),
          Obx(() => cntrller.libraryArtists.isNotEmpty
              ? ListWidget(cntrller.libraryArtists, "Library Artists", true)
              : Expanded(
                  child: Center(
                      child: Text(
                  "noBookmarks".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ))))
        ],
      ),
    );
  }
}
