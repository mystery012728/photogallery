import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';
import 'full_image_view.dart';
import 'video_player_page.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  List<AssetPathEntity> albums = [];
  bool isLoading = true;
  bool hasPermission = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadAlbums();
  }

  Future<void> _requestPermissionAndLoadAlbums() async {
    final PermissionState permission = await PhotoManager.requestPermissionExtend();

    if (permission.isAuth) {
      setState(() {
        hasPermission = true;
      });
      await _loadAlbums();
    } else {
      setState(() {
        hasPermission = false;
        isLoading = false;
      });
      _showPermissionDialog();
    }
  }

  Future<void> _loadAlbums() async {
    try {
      final List<AssetPathEntity> allAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: false,
      );

      setState(() {
        albums = allAlbums;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading albums: $e')),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'This app needs access to your photos to display albums. Please grant permission in settings.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Settings'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Container();
    }

    if (!hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.photo_album_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 20),
            const Text(
              'Permission Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Please grant photo access permission to view your albums',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _requestPermissionAndLoadAlbums,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (albums.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_album_outlined,
              size: 80,
              color: Colors.grey,
            ),
            SizedBox(height: 20),
            Text(
              'No Albums Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'No photo albums were found on your device',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        return AlbumTile(album: albums[index]);
      },
    );
  }
}

class AlbumTile extends StatelessWidget {
  final AssetPathEntity album;

  const AlbumTile({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: album.assetCountAsync,
      builder: (context, countSnapshot) {
        final count = countSnapshot.data ?? 0;

        return FutureBuilder<List<AssetEntity>>(
          future: album.getAssetListPaged(page: 0, size: 1),
          builder: (context, assetsSnapshot) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _openAlbumDetails(context);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Album thumbnail
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[300],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildThumbnail(assetsSnapshot.data),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Album info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$count ${count == 1 ? 'item' : 'items'}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Arrow icon
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThumbnail(List<AssetEntity>? assets) {
    if (assets == null || assets.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Icon(
          Icons.photo_album,
          color: Colors.grey,
          size: 30,
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: assets.first.thumbnailDataWithSize(const ThumbnailSize(120, 120)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: 60,
            height: 60,
          );
        }
        return Container(
          color: Colors.grey[300],
        );
      },
    );
  }

  void _openAlbumDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AlbumDetailsPage(album: album),
      ),
    );
  }
}

class AlbumDetailsPage extends StatefulWidget {
  final AssetPathEntity album;

  const AlbumDetailsPage({super.key, required this.album});

  @override
  State<AlbumDetailsPage> createState() => _AlbumDetailsPageState();
}

class _AlbumDetailsPageState extends State<AlbumDetailsPage> {
  List<AssetEntity> assets = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbumAssets();
  }

  Future<void> _loadAlbumAssets() async {
    try {
      final List<AssetEntity> albumAssets = await widget.album.getAssetListPaged(
        page: 0,
        size: 1000,
      );

      setState(() {
        assets = albumAssets;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading album: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Container();
    }

    if (assets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 80,
              color: Colors.grey,
            ),
            SizedBox(height: 20),
            Text(
              'No Media Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'This album is empty',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        return AlbumAssetThumbnail(asset: assets[index]);
      },
    );
  }
}

class AlbumAssetThumbnail extends StatelessWidget {
  final AssetEntity asset;

  const AlbumAssetThumbnail({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          return GestureDetector(
            onTap: () {
              _openAsset(context);
            },
            child: Container(
              child: ClipRRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                    ),
                    // Video indicator
                    if (asset.type == AssetType.video)
                      const Positioned(
                        bottom: 4,
                        right: 4,
                        child: Icon(
                          Icons.play_circle_filled,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[300],
          ),
        );
      },
    );
  }

  void _openAsset(BuildContext context) {
    if (asset.type == AssetType.image) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => FullImageView(asset: asset),
        ),
      );
    } else if (asset.type == AssetType.video) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(asset: asset),
        ),
      );
    }
  }
}
