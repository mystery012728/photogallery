import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photogallery/Pages/full_image_view.dart';
import 'dart:typed_data';
import 'package:photogallery/backend/enhanced_media_cache.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> with TickerProviderStateMixin {
  final EnhancedMediaCache _mediaCache = EnhancedMediaCache();
  List<AssetEntity> photos = [];
  bool hasPermission = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // New state variables for selection
  final Set<AssetEntity> _selectedPhotos = {};
  bool _isSelectionMode = false;
  // New: Track selected dates for group selection
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
    _loadPhotos();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    try {
      final permission = await _mediaCache.checkPermission();

      if (!permission) {
        setState(() => hasPermission = false);
        _showPermissionDialog();
        return;
      }

      setState(() => hasPermission = true);
      final loadedPhotos = await _mediaCache.loadPhotos();

      if (mounted) {
        setState(() => photos = loadedPhotos);
        _fadeController.forward();

        // Silent refresh to load all photos after 0.001 seconds
        Future.delayed(const Duration(milliseconds: 1), () async {
          if (mounted && !_mediaCache.photosLoaded) {
            final allPhotos = await _mediaCache.loadAllPhotos();
            if (mounted) {
              setState(() => photos = allPhotos);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading photos: $e')),
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
            'This app needs access to your photos to display them. Please grant permission in settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _mediaCache.clearCache();
              _loadPhotos();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // New method to toggle photo selection
  void _togglePhotoSelection(AssetEntity asset) {
    setState(() {
      if (_selectedPhotos.contains(asset)) {
        _selectedPhotos.remove(asset);
      } else {
        _selectedPhotos.add(asset);
      }
      _isSelectionMode = _selectedPhotos.isNotEmpty;
    });
  }

  // New method to exit selection mode
  void _exitSelectionMode() {
    setState(() {
      _selectedPhotos.clear();
      _isSelectionMode = false;
    });
  }

  // New method to select all photos
  void _selectAllPhotos() {
    setState(() {
      _selectedPhotos.clear();
      _selectedPhotos.addAll(photos);
      _isSelectionMode = _selectedPhotos.isNotEmpty;
    });
  }

  // Placeholder for delete functionality
  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Photos?'),
        content: Text(
            'Are you sure you want to delete ${_selectedPhotos.length} photo(s)? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // New method for sharing selected photos
  Future<void> _shareSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;
    final List<XFile> files = [];
    for (final asset in _selectedPhotos) {
      final file = await asset.file;
      if (file != null && await file.exists()) {
        files.add(XFile(file.path));
      }
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files,
          text: 'Sharing ${files.length} photo(s) from PhotoGallery');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid files to share.')),
      );
    }
  }

  // Helper: Check if all photos for a date are selected
  bool _isDateFullySelected(String dateKey, List<AssetEntity> dayPhotos) {
    return dayPhotos.isNotEmpty &&
        dayPhotos.every((photo) => _selectedPhotos.contains(photo));
  }

  // Helper: Toggle selection for all photos of a date
  void _toggleDateSelection(String dateKey, List<AssetEntity> dayPhotos) {
    setState(() {
      final allSelected = _isDateFullySelected(dateKey, dayPhotos);
      if (allSelected) {
        // Deselect all photos for this date
        for (final photo in dayPhotos) {
          _selectedPhotos.remove(photo);
        }
        _selectedDates.remove(dateKey);
      } else {
        // Select all photos for this date
        for (final photo in dayPhotos) {
          _selectedPhotos.add(photo);
        }
        _selectedDates.add(dateKey);
      }
      _isSelectionMode = _selectedPhotos.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _exitSelectionMode();
          return false; // Prevent pop
        }
        return true; // Allow pop
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSelectionMode
              ? Text('${_selectedPhotos.length} selected')
              : const Text('Photos'),
          centerTitle: true,
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            if (_isSelectionMode) ...[
              IconButton(
                icon: const Icon(Icons.cancel),
                onPressed: _exitSelectionMode,
                tooltip: 'Exit Selection',
              ),
              if (_selectedPhotos.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.share), // Share icon
                  onPressed: _shareSelectedPhotos,
                  tooltip: 'Share Selected',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteSelectedPhotos,
                  tooltip: 'Delete Selected',
                ),
              ],
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'select_all') {
                    _selectAllPhotos();
                  } else {
                    // Handle more options here if needed
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('More option selected: $value')),
                    );
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
        Icons.photo_library_outlined,
        'Permission Required',
        'Please grant photo access permission to view your photos',
        'Grant Permission',
        () {
          _mediaCache.clearCache();
          _loadPhotos();
        },
      );
    }

    if (photos.isEmpty) {
      return _buildCenterMessage(
        Icons.photo_library_outlined,
        'No Photos Found',
        'No photos were found on your device',
        null,
        null,
      );
    }

    final groupedPhotos = _groupPhotosByDate(photos);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: () async {
          _mediaCache.refreshAllData();
          await _loadPhotos();
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: groupedPhotos.length,
          itemBuilder: (context, index) {
            final dateKey = groupedPhotos.keys.elementAt(index);
            final dayPhotos = groupedPhotos[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date header with tick for selection mode
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
                          _isDateFullySelected(dateKey, dayPhotos)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _isDateFullySelected(dateKey, dayPhotos)
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        onPressed: () =>
                            _toggleDateSelection(dateKey, dayPhotos),
                        tooltip: _isDateFullySelected(dateKey, dayPhotos)
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
                  itemCount: dayPhotos.length,
                  itemBuilder: (context, photoIndex) {
                    final asset = dayPhotos[photoIndex];
                    final isSelected = _selectedPhotos.contains(asset);
                    return OptimizedPhotoThumbnail(
                      asset: asset,
                      isSelectionMode: _isSelectionMode,
                      isSelected: isSelected,
                      onToggleSelection: _togglePhotoSelection,
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

  Map<String, List<AssetEntity>> _groupPhotosByDate(List<AssetEntity> photos) {
    final Map<String, List<AssetEntity>> grouped = {};

    for (final photo in photos) {
      final date = photo.createDateTime;
      final dateKey = '${date.day}/${date.month}/${date.year}';

      grouped.putIfAbsent(dateKey, () => []).add(photo);
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

class OptimizedPhotoThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(AssetEntity) onToggleSelection;
  final EnhancedMediaCache mediaCache;

  const OptimizedPhotoThumbnail({
    super.key,
    required this.asset,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.mediaCache,
  });

  @override
  State<OptimizedPhotoThumbnail> createState() =>
      _OptimizedPhotoThumbnailState();
}

class _OptimizedPhotoThumbnailState extends State<OptimizedPhotoThumbnail>
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
          _showFullImage(context);
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
            // Add error handling for image loading
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

  void _showFullImage(BuildContext context) {
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
  }
}

// Keep the old PhotoThumbnail for backward compatibility
class PhotoThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(AssetEntity) onToggleSelection;

  const PhotoThumbnail({
    super.key,
    required this.asset,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggleSelection,
  });

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail>
    with SingleTickerProviderStateMixin {
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
      final data = await widget.asset
          .thumbnailDataWithSize(const ThumbnailSize(200, 200));
      if (mounted && data != null) {
        setState(() => _thumbnailData = data);
        _controller.forward();
      }
    } catch (e) {
      // Handle error silently
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
          _showFullImage(context);
        }
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[300]),
        child: _thumbnailData != null
            ? FadeTransition(
                opacity: _animation,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _thumbnailData!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                    if (widget.isSelected)
                      Container(
                        color: Colors.blue
                            .withOpacity(0.4), // Semi-transparent blue overlay
                      ),
                    if (widget.isSelected)
                      const Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.blue, // Blue tick icon
                          size: 24,
                        ),
                      ),
                  ],
                ),
              )
            : Container(color: Colors.grey[300]),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
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
  }
}
