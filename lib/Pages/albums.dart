import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photogallery/Pages/full_image_view.dart';
import 'package:photogallery/Pages/video_player_page.dart';
import 'dart:typed_data';

import 'package:photogallery/backend/enhanced_media_cache.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> with TickerProviderStateMixin {
  final EnhancedMediaCache _mediaCache = EnhancedMediaCache();
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
      final permission = await _mediaCache.checkPermission();

      if (!permission) {
        setState(() => hasPermission = false);
        _showPermissionDialog();
        return;
      }

      setState(() => hasPermission = true);
      final loadedAlbums = await _mediaCache.loadAlbums();

      if (mounted) {
        setState(() => albums = loadedAlbums);
        _fadeController.forward();

        // Silent refresh to load all albums after 0.001 seconds
        Future.delayed(const Duration(milliseconds: 1), () async {
          if (mounted && !_mediaCache.albumsLoaded) {
            final allAlbums = await _mediaCache.loadAllAlbums();
            if (mounted) {
              setState(() => albums = allAlbums);
            }
          }
        });
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
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'This app needs access to your photos to display albums. Please grant permission in settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
      ),
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
      return _buildCenterMessage(
        Icons.photo_album_outlined,
        'Permission Required',
        'Please grant photo access permission to view your albums',
        'Grant Permission',
        () {
          _mediaCache.clearCache();
          _loadAlbums();
        },
      );
    }

    if (albums.isEmpty) {
      return _buildCenterMessage(
        Icons.photo_album_outlined,
        'No Albums Found',
        'No photo albums were found on your device',
        null,
        null,
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

  Widget _buildCenterMessage(IconData icon, String title, String subtitle,
      String? buttonText, VoidCallback? onPressed) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            if (buttonText != null && onPressed != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onPressed, child: Text(buttonText)),
            ],
          ],
        ),
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

class _AlbumTileState extends State<AlbumTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _assetCount = 0;
  Uint8List? _thumbnailData;
  bool _isLoading = true;

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
      setState(() => _isLoading = true);

      final countFuture = widget.album.assetCountAsync;
      final assetsFuture = widget.album.getAssetListPaged(page: 0, size: 1);

      final results = await Future.wait([countFuture, assetsFuture]);
      final count = results[0] as int;
      final assets = results[1] as List<AssetEntity>;

      if (mounted) {
        setState(() => _assetCount = count);

        if (assets.isNotEmpty) {
          final thumbnailData = await assets.first
              .thumbnailDataWithSize(const ThumbnailSize(120, 120));
          if (mounted && thumbnailData != null) {
            setState(() => _thumbnailData = thumbnailData);
          }
        }
        setState(() => _isLoading = false);
        _controller.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAlbumDetails(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[300],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildThumbnailContent(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.album.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_assetCount ${_assetCount == 1 ? 'item' : 'items'}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (_isLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          color: Colors.white,
        ),
      );
    }

    if (_thumbnailData != null) {
      return Image.memory(_thumbnailData!,
          fit: BoxFit.cover, width: 60, height: 60);
    }

    return Container(
      color: Colors.grey[300],
      child: const Icon(Icons.photo_album, color: Colors.grey, size: 30),
    );
  }

  void _openAlbumDetails(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            AlbumDetailsPage(album: widget.album),
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

class _AlbumDetailsPageState extends State<AlbumDetailsPage>
    with TickerProviderStateMixin {
  final EnhancedMediaCache _mediaCache = EnhancedMediaCache();
  List<AssetEntity> assets = [];
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Selection state
  final Set<AssetEntity> _selectedAssets = {};
  bool _isSelectionMode = false;
  final Set<String> _selectedDates = {};

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
      final loadedAssets = await _mediaCache.loadAlbumAssets(widget.album);

      if (mounted) {
        setState(() => assets = loadedAssets);
        _fadeController.forward();

        // Silent refresh to ensure all assets are loaded
        Future.delayed(const Duration(milliseconds: 1), () async {
          if (mounted) {
            final allAssets =
                await _mediaCache.loadAllAlbumAssets(widget.album);
            if (mounted) {
              setState(() => assets = allAssets);
            }
          }
        });
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
      final loadedAssets =
          await _mediaCache.loadAlbumAssets(widget.album, forceReload: true);

      if (mounted) {
        setState(() => assets = loadedAssets);
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

  // Toggle asset selection
  void _toggleAssetSelection(AssetEntity asset) {
    setState(() {
      if (_selectedAssets.contains(asset)) {
        _selectedAssets.remove(asset);
      } else {
        _selectedAssets.add(asset);
      }
      _isSelectionMode = _selectedAssets.isNotEmpty;
    });
  }

  // Exit selection mode
  void _exitSelectionMode() {
    setState(() {
      _selectedAssets.clear();
      _isSelectionMode = false;
    });
  }

  // Select all assets
  void _selectAllAssets() {
    setState(() {
      _selectedAssets.clear();
      _selectedAssets.addAll(assets);
      _isSelectionMode = _selectedAssets.isNotEmpty;
    });
  }

  // Share selected assets
  Future<void> _shareSelectedAssets() async {
    if (_selectedAssets.isEmpty) return;
    final List<XFile> files = [];
    for (final asset in _selectedAssets) {
      final file = await asset.file;
      if (file != null && await file.exists()) {
        files.add(XFile(file.path));
      }
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files,
          text: 'Sharing ${files.length} item(s) from PhotoGallery');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid files to share.')),
      );
    }
  }

  // Check if all assets for a date are selected
  bool _isDateFullySelected(String dateKey, List<AssetEntity> dayAssets) {
    return dayAssets.isNotEmpty &&
        dayAssets.every((asset) => _selectedAssets.contains(asset));
  }

  // Toggle selection for all assets of a date
  void _toggleDateSelection(String dateKey, List<AssetEntity> dayAssets) {
    setState(() {
      final allSelected = _isDateFullySelected(dateKey, dayAssets);
      if (allSelected) {
        for (final asset in dayAssets) {
          _selectedAssets.remove(asset);
        }
        _selectedDates.remove(dateKey);
      } else {
        for (final asset in dayAssets) {
          _selectedAssets.add(asset);
        }
        _selectedDates.add(dateKey);
      }
      _isSelectionMode = _selectedAssets.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedAssets.length} selected')
            : Text(widget.album.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: _exitSelectionMode,
              tooltip: 'Exit Selection',
            ),
            if (_selectedAssets.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _shareSelectedAssets,
                tooltip: 'Share Selected',
              ),
            ],
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'select_all') {
                  _selectAllAssets();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'select_all',
                  child: Text('Select All'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
              tooltip: 'More Options',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAlbumAssets,
              tooltip: 'Refresh Album',
            ),
          ],
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
              Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 20),
              Text('No Media Found',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text('This album is empty', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final groupedAssets = _groupAssetsByDate(assets);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: _refreshAlbumAssets,
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: groupedAssets.length,
          itemBuilder: (context, index) {
            final dateKey = groupedAssets.keys.elementAt(index);
            final dayAssets = groupedAssets[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          dateKey,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (_isSelectionMode)
                      IconButton(
                        icon: Icon(
                          _isDateFullySelected(dateKey, dayAssets)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _isDateFullySelected(dateKey, dayAssets)
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        onPressed: () =>
                            _toggleDateSelection(dateKey, dayAssets),
                        tooltip: _isDateFullySelected(dateKey, dayAssets)
                            ? 'Deselect all for this date'
                            : 'Select all for this date',
                      ),
                  ],
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                  ),
                  itemCount: dayAssets.length,
                  itemBuilder: (context, assetIndex) {
                    final asset = dayAssets[assetIndex];
                    final isSelected = _selectedAssets.contains(asset);
                    return OptimizedAlbumAssetThumbnail(
                      asset: asset,
                      isSelectionMode: _isSelectionMode,
                      isSelected: isSelected,
                      onToggleSelection: _toggleAssetSelection,
                      mediaCache: _mediaCache,
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Map<String, List<AssetEntity>> _groupAssetsByDate(List<AssetEntity> assets) {
    final Map<String, List<AssetEntity>> grouped = {};

    for (final asset in assets) {
      final date = asset.createDateTime;
      final dateKey = '${date.day}/${date.month}/${date.year}';
      grouped.putIfAbsent(dateKey, () => []).add(asset);
    }

    // Sort by actual date (newest first)
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) {
        final dateA = _parseDateKey(a.key);
        final dateB = _parseDateKey(b.key);
        return dateB.compareTo(dateA); // Newest first
      });

    return Map.fromEntries(sortedEntries);
  }

  DateTime _parseDateKey(String dateKey) {
    final parts = dateKey.split('/');
    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final year = int.parse(parts[2]);
    return DateTime(year, month, day);
  }
}

class AlbumAssetThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(AssetEntity) onToggleSelection;

  const AlbumAssetThumbnail({
    super.key,
    required this.asset,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onToggleSelection,
  });

  @override
  State<AlbumAssetThumbnail> createState() => _AlbumAssetThumbnailState();
}

class _AlbumAssetThumbnailState extends State<AlbumAssetThumbnail>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Uint8List? _thumbnailData;
  bool _isLoading = true;
  bool _hasError = false;
  final EnhancedMediaCache _mediaCache = EnhancedMediaCache();

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
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // First, try to get from cache
      final cachedThumbnail = _mediaCache.getCachedThumbnail(widget.asset.id);
      if (cachedThumbnail != null) {
        if (mounted) {
          setState(() {
            _thumbnailData = cachedThumbnail;
            _isLoading = false;
          });
          _controller.forward();
        }
        return;
      }

      // If not in cache, load from asset
      final data = await widget.asset
          .thumbnailDataWithSize(const ThumbnailSize(150, 150));

      if (mounted && data != null) {
        setState(() {
          _thumbnailData = data;
          _isLoading = false;
        });
        _controller.forward();
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        widget.onToggleSelection(widget.asset);
      },
      onTap: () {
        if (widget.isSelectionMode) {
          widget.onToggleSelection(widget.asset);
        } else {
          _openAsset(context);
        }
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[300]),
        child: _buildThumbnailContent(),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (_isLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          color: Colors.white,
        ),
      );
    }

    if (_hasError || _thumbnailData == null) {
      return Container(
        color: Colors.grey[300],
        child: const Icon(
          Icons.broken_image,
          color: Colors.grey,
          size: 30,
        ),
      );
    }

    return FadeTransition(
      opacity: _animation,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _thumbnailData!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                  size: 30,
                ),
              );
            },
          ),
          if (widget.asset.type == AssetType.video)
            const Positioned(
              bottom: 4,
              right: 4,
              child:
                  Icon(Icons.play_circle_filled, color: Colors.white, size: 20),
            ),
          if (widget.isSelected)
            Container(
              color: Colors.blue.withOpacity(0.4),
            ),
          if (widget.isSelected)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.check_circle,
                color: Colors.blue,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  void _openAsset(BuildContext context) {
    if (widget.asset.type == AssetType.image) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FullImageView(asset: widget.asset),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } else if (widget.asset.type == AssetType.video) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              VideoPlayerPage(asset: widget.asset),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }
}

class OptimizedAlbumAssetThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(AssetEntity) onToggleSelection;
  final EnhancedMediaCache mediaCache;

  const OptimizedAlbumAssetThumbnail({
    super.key,
    required this.asset,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.mediaCache,
  });

  @override
  State<OptimizedAlbumAssetThumbnail> createState() =>
      _OptimizedAlbumAssetThumbnailState();
}

class _OptimizedAlbumAssetThumbnailState
    extends State<OptimizedAlbumAssetThumbnail>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Uint8List? _thumbnailData;
  bool _isLoading = true;
  bool _hasError = false;

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
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // First, try to get from cache
      final cachedThumbnail =
          widget.mediaCache.getCachedThumbnail(widget.asset.id);
      if (cachedThumbnail != null) {
        if (mounted) {
          setState(() {
            _thumbnailData = cachedThumbnail;
            _isLoading = false;
          });
          _controller.forward();
        }
        return;
      }

      // If not in cache, load from asset
      final data = await widget.asset
          .thumbnailDataWithSize(const ThumbnailSize(150, 150));

      if (mounted && data != null) {
        setState(() {
          _thumbnailData = data;
          _isLoading = false;
        });
        _controller.forward();
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        widget.onToggleSelection(widget.asset);
      },
      onTap: () {
        if (widget.isSelectionMode) {
          widget.onToggleSelection(widget.asset);
        } else {
          _openAsset(context);
        }
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[300]),
        child: _buildThumbnailContent(),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (_isLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          color: Colors.white,
        ),
      );
    }

    if (_hasError || _thumbnailData == null) {
      return Container(
        color: Colors.grey[300],
        child: const Icon(
          Icons.broken_image,
          color: Colors.grey,
          size: 30,
        ),
      );
    }

    return FadeTransition(
      opacity: _animation,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _thumbnailData!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                  size: 30,
                ),
              );
            },
          ),
          if (widget.asset.type == AssetType.video)
            const Positioned(
              bottom: 4,
              right: 4,
              child:
                  Icon(Icons.play_circle_filled, color: Colors.white, size: 20),
            ),
          if (widget.isSelected)
            Container(
              color: Colors.blue.withOpacity(0.4),
            ),
          if (widget.isSelected)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.check_circle,
                color: Colors.blue,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  void _openAsset(BuildContext context) {
    if (widget.asset.type == AssetType.image) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FullImageView(asset: widget.asset),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } else if (widget.asset.type == AssetType.video) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              VideoPlayerPage(asset: widget.asset),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }
}
