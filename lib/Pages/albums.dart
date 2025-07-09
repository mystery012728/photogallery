import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photogallery/Pages/full_image_view.dart';
import 'package:photogallery/Pages/video_player_page.dart';
import 'dart:typed_data';

import 'package:photogallery/backend/media_cache.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> with TickerProviderStateMixin {
  final MediaCache _mediaCache = MediaCache();
  List<AssetPathEntity> albums = [];
  bool hasPermission = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _loadAlbums();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    try {
      // Check permission first
      final permission = await _mediaCache.checkPermission();

      if (!permission) {
        setState(() {
          hasPermission = false;
        });
        _showPermissionDialog();
        return;
      }

      setState(() {
        hasPermission = true;
      });

      // Load albums from cache (should be instant if cached)
      final loadedAlbums = await _mediaCache.loadAlbums();

      if (mounted) {
        setState(() {
          albums = loadedAlbums;
        });
        _fadeController.forward();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading albums: $e')),
        );
        _fadeController.forward();
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
                _mediaCache.clearCache();
                _loadAlbums();
              },
              child: const Text('Retry'),
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
    if (!hasPermission) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
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
                onPressed: () {
                  _mediaCache.clearCache();
                  _loadAlbums();
                },
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (albums.isEmpty) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: const Center(
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
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,

        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            return AlbumTile(album: albums[index]);
          },
        ),
    );
  }
}

class AlbumTile extends StatefulWidget {
  final AssetPathEntity album;

  const AlbumTile({super.key, required this.album});

  @override
  State<AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<AlbumTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _assetCount = 0;
  Uint8List? _thumbnailData;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _loadAlbumData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAlbumData() async {
    try {
      // Load count and thumbnail in parallel
      final countFuture = widget.album.assetCountAsync;
      final assetsFuture = widget.album.getAssetListPaged(page: 0, size: 1);

      final results = await Future.wait([countFuture, assetsFuture]);
      final count = results[0] as int;
      final assets = results[1] as List<AssetEntity>;

      if (mounted) {
        setState(() {
          _assetCount = count;
        });

        if (assets.isNotEmpty) {
          final thumbnailData = await assets.first.thumbnailDataWithSize(const ThumbnailSize(120, 120));
          if (mounted && thumbnailData != null) {
            setState(() {
              _thumbnailData = thumbnailData;
            });
          }
        }
        _controller.forward();
      }
    } catch (e) {
      if (mounted) {
        _controller.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Card(
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
                    child: _thumbnailData != null
                        ? Image.memory(
                      _thumbnailData!,
                      fit: BoxFit.cover,
                      width: 60,
                      height: 60,
                    )
                        : Container(
                      color: Colors.grey[300],
                      child: const Icon(
                        Icons.photo_album,
                        color: Colors.grey,
                        size: 30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Album info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.album.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_assetCount ${_assetCount == 1 ? 'item' : 'items'}',
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
      ),
    );
  }

  void _openAlbumDetails(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AlbumDetailsPage(album: widget.album),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
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

class _AlbumDetailsPageState extends State<AlbumDetailsPage> with TickerProviderStateMixin {
  final MediaCache _mediaCache = MediaCache();
  List<AssetEntity> assets = [];
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _loadAlbumAssets();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbumAssets() async {
    try {
      // Load album assets from cache (should be instant if cached)
      final loadedAssets = await _mediaCache.loadAlbumAssets(widget.album);

      if (mounted) {
        setState(() {
          assets = loadedAssets;
        });
        _fadeController.forward();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading album: $e')),
        );
        _fadeController.forward();
      }
    }
  }

  Future<void> _refreshAlbumAssets() async {
    _fadeController.reset();

    try {
      final loadedAssets = await _mediaCache.loadAlbumAssets(widget.album, forceReload: true);

      if (mounted) {
        setState(() {
          assets = loadedAssets;
        });
        _fadeController.forward();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing album: $e')),
        );
        _fadeController.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAlbumAssets,
            tooltip: 'Refresh Album',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (assets.isEmpty) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: const Center(
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
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: _refreshAlbumAssets,
        child: GridView.builder(
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
        ),
      ),
    );
  }
}

class AlbumAssetThumbnail extends StatefulWidget {
  final AssetEntity asset;

  const AlbumAssetThumbnail({super.key, required this.asset});

  @override
  State<AlbumAssetThumbnail> createState() => _AlbumAssetThumbnailState();
}

class _AlbumAssetThumbnailState extends State<AlbumAssetThumbnail> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Uint8List? _thumbnailData;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _loadThumbnail();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    try {
      final data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
      if (mounted && data != null) {
        setState(() {
          _thumbnailData = data;
        });
        _controller.forward();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _openAsset(context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
        ),
        child: _thumbnailData != null
            ? FadeTransition(
          opacity: _animation,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                _thumbnailData!,
                fit: BoxFit.cover,
              ),
              // Video indicator
              if (widget.asset.type == AssetType.video)
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
        )
            : Container(
          decoration: BoxDecoration(
            color: Colors.grey[300],
          ),
        ),
      ),
    );
  }

  void _openAsset(BuildContext context) {
    if (widget.asset.type == AssetType.image) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => FullImageView(asset: widget.asset),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } else if (widget.asset.type == AssetType.video) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => VideoPlayerPage(asset: widget.asset),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }
}
