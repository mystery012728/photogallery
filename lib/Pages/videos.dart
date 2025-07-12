import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photogallery/Pages/video_player_page.dart';
import 'dart:typed_data';

import 'package:photogallery/backend/enhanced_media_cache.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> with TickerProviderStateMixin {
  final EnhancedMediaCache _mediaCache = EnhancedMediaCache();
  List<AssetEntity> videos = [];
  bool hasPermission = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Selection state
  final Set<AssetEntity> _selectedVideos = {};
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
    _loadVideos();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos() async {
    try {
      final permission = await _mediaCache.checkPermission();

      if (!permission) {
        setState(() => hasPermission = false);
        _showPermissionDialog();
        return;
      }

      setState(() => hasPermission = true);
      final loadedVideos = await _mediaCache.loadVideos();

      if (mounted) {
        setState(() => videos = loadedVideos);
        _fadeController.forward();

        // Silent refresh to load all videos after 0.001 seconds
        Future.delayed(const Duration(milliseconds: 1), () async {
          if (mounted && !_mediaCache.videosLoaded) {
            final allVideos = await _mediaCache.loadAllVideos();
            if (mounted) {
              setState(() => videos = allVideos);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading videos: $e')),
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
            'This app needs access to your videos to display them. Please grant permission in settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _mediaCache.clearCache();
              _loadVideos();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // Toggle video selection
  void _toggleVideoSelection(AssetEntity asset) {
    setState(() {
      if (_selectedVideos.contains(asset)) {
        _selectedVideos.remove(asset);
      } else {
        _selectedVideos.add(asset);
      }
      _isSelectionMode = _selectedVideos.isNotEmpty;
    });
  }

  // Exit selection mode
  void _exitSelectionMode() {
    setState(() {
      _selectedVideos.clear();
      _isSelectionMode = false;
    });
  }

  // Select all videos
  void _selectAllVideos() {
    setState(() {
      _selectedVideos.clear();
      _selectedVideos.addAll(videos);
      _isSelectionMode = _selectedVideos.isNotEmpty;
    });
  }

  // Share selected videos
  Future<void> _shareSelectedVideos() async {
    if (_selectedVideos.isEmpty) return;
    final List<XFile> files = [];
    for (final asset in _selectedVideos) {
      final file = await asset.file;
      if (file != null && await file.exists()) {
        files.add(XFile(file.path));
      }
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files,
          text: 'Sharing ${files.length} video(s) from PhotoGallery');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid files to share.')),
      );
    }
  }

  // Check if all videos for a date are selected
  bool _isDateFullySelected(String dateKey, List<AssetEntity> dayVideos) {
    return dayVideos.isNotEmpty &&
        dayVideos.every((video) => _selectedVideos.contains(video));
  }

  // Toggle selection for all videos of a date
  void _toggleDateSelection(String dateKey, List<AssetEntity> dayVideos) {
    setState(() {
      final allSelected = _isDateFullySelected(dateKey, dayVideos);
      if (allSelected) {
        for (final video in dayVideos) {
          _selectedVideos.remove(video);
        }
        _selectedDates.remove(dateKey);
      } else {
        for (final video in dayVideos) {
          _selectedVideos.add(video);
        }
        _selectedDates.add(dateKey);
      }
      _isSelectionMode = _selectedVideos.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _exitSelectionMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSelectionMode
              ? Text('${_selectedVideos.length} selected')
              : const Text('Videos'),
          centerTitle: true,
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            if (_isSelectionMode) ...[
              IconButton(
                icon: const Icon(Icons.cancel),
                onPressed: _exitSelectionMode,
                tooltip: 'Exit Selection',
              ),
              if (_selectedVideos.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _shareSelectedVideos,
                  tooltip: 'Share Selected',
                ),
              ],
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'select_all') {
                    _selectAllVideos();
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
            ],
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (!hasPermission) {
      return _buildCenterMessage(
        Icons.video_library_outlined,
        'Permission Required',
        'Please grant photo access permission to view your videos',
        'Grant Permission',
        () {
          _mediaCache.clearCache();
          _loadVideos();
        },
      );
    }

    if (videos.isEmpty) {
      return _buildCenterMessage(
        Icons.video_library_outlined,
        'No Videos Found',
        'No videos were found on your device',
        null,
        null,
      );
    }

    final groupedVideos = _groupVideosByDate(videos);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: () async {
          _mediaCache.refreshAllData();
          await _loadVideos();
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: groupedVideos.length,
          itemBuilder: (context, index) {
            final dateKey = groupedVideos.keys.elementAt(index);
            final dayVideos = groupedVideos[dateKey]!;

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
                          _isDateFullySelected(dateKey, dayVideos)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _isDateFullySelected(dateKey, dayVideos)
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        onPressed: () =>
                            _toggleDateSelection(dateKey, dayVideos),
                        tooltip: _isDateFullySelected(dateKey, dayVideos)
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
                  itemCount: dayVideos.length,
                  itemBuilder: (context, videoIndex) {
                    final asset = dayVideos[videoIndex];
                    final isSelected = _selectedVideos.contains(asset);
                    return OptimizedVideoThumbnail(
                      asset: asset,
                      isSelectionMode: _isSelectionMode,
                      isSelected: isSelected,
                      onToggleSelection: _toggleVideoSelection,
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

  Map<String, List<AssetEntity>> _groupVideosByDate(List<AssetEntity> videos) {
    final Map<String, List<AssetEntity>> grouped = {};

    for (final video in videos) {
      final date = video.createDateTime;
      final dateKey = '${date.day}/${date.month}/${date.year}';

      grouped.putIfAbsent(dateKey, () => []).add(video);
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

class VideoThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(AssetEntity) onToggleSelection;

  const VideoThumbnail({
    super.key,
    required this.asset,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onToggleSelection,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail>
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
          _playVideo(context);
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
          // Dark overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.3),
                ],
              ),
            ),
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
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7)),
              child: Text(
                _formatDuration(widget.asset.videoDuration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _playVideo(BuildContext context) async {
    try {
      final file = await widget.asset.file;
      if (file == null || !await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video file is not accessible'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                VideoPlayerPage(asset: widget.asset),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class OptimizedVideoThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(AssetEntity) onToggleSelection;
  final EnhancedMediaCache mediaCache;

  const OptimizedVideoThumbnail({
    super.key,
    required this.asset,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.mediaCache,
  });

  @override
  State<OptimizedVideoThumbnail> createState() =>
      _OptimizedVideoThumbnailState();
}

class _OptimizedVideoThumbnailState extends State<OptimizedVideoThumbnail>
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
          _playVideo(context);
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
          // Dark overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.3),
                ],
              ),
            ),
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
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7)),
              child: Text(
                _formatDuration(widget.asset.videoDuration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _playVideo(BuildContext context) async {
    try {
      final file = await widget.asset.file;
      if (file == null || !await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video file is not accessible'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                VideoPlayerPage(asset: widget.asset),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
