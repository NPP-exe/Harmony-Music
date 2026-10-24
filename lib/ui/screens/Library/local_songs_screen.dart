import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../player/player_controller.dart';
import '../../widgets/image_widget.dart';
import 'local_songs_controller.dart';

class LocalSongsScreen extends StatelessWidget {
  const LocalSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Music'),
      ),
      body: const LocalSongsView(),
    );
  }
}

class LocalSongsView extends StatelessWidget {
  const LocalSongsView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<LocalSongsController>()) {
      Get.lazyPut<LocalSongsController>(() => LocalSongsController());
    }
    final controller = Get.find<LocalSongsController>();
    final playerController = Get.find<PlayerController>();

    return Column(
      children: [
        // Search bar & Action Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: controller.searchController,
                    onChanged: controller.onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search local songs...',
                      hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withAlpha(128),
                          ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: Obx(
                        () => controller.searchQuery.value.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: controller.clearSearch,
                              )
                            : const SizedBox.shrink(),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.secondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Add folder',
                icon: const Icon(Icons.create_new_folder, size: 20),
                onPressed: controller.pickAndAddFolder,
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Add files',
                icon: const Icon(Icons.add, size: 20),
                onPressed: controller.pickAndAddFiles,
              ),
            ],
          ),
        ),

        // Scanning progress bar
        Obx(
          () => controller.isScanning.value
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: LinearProgressIndicator(),
                )
              : const SizedBox.shrink(),
        ),

        // Count header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Obx(
                () => Text(
                  '${controller.filteredSongsList.length} local song${controller.filteredSongsList.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withAlpha(180),
                      ),
                ),
              ),
            ],
          ),
        ),

        // Content List
        Expanded(
          child: Obx(() {
            if (!controller.isFetched.value) {
              return const Center(child: CircularProgressIndicator());
            }

            if (controller.localSongsList.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No local songs added',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add a music folder to play your local tracks with lyrics and album art',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(160),
                            ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.create_new_folder),
                        label: const Text('Add Music Folder'),
                        onPressed: controller.pickAndAddFolder,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.audio_file),
                        label: const Text('Add Individual Files'),
                        onPressed: controller.pickAndAddFiles,
                      ),
                    ],
                  ),
                ),
              );
            }

            if (controller.filteredSongsList.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No songs match "${controller.searchQuery.value}"',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: controller.clearSearch,
                      child: const Text('Clear search'),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 120),
              itemCount: controller.filteredSongsList.length,
              itemBuilder: (context, index) {
                final song = controller.filteredSongsList[index];
                return _LocalSongTile(
                  song: song,
                  onTap: () {
                    playerController.playLocalSong(
                        song, controller.filteredSongsList.toList());
                  },
                  onDelete: () => controller.removeSong(song),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _LocalSongTile extends StatelessWidget {
  final MediaItem song;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LocalSongTile({
    required this.song,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ImageWidget(
        song: song,
        size: 48,
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        song.artist ?? 'Unknown Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withAlpha(180),
            ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          if (value == 'play') {
            onTap();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'play',
            child: Row(
              children: [
                Icon(Icons.play_arrow, size: 20),
                SizedBox(width: 8),
                Text('Play'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20),
                SizedBox(width: 8),
                Text('Remove from local'),
              ],
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
