import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photogallery/Pages/full_image_view.dart';
import 'dart:typed_data';

import 'package:photogallery/backend/media_cache.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> with TickerProviderStateMixin {
  final MediaCache _mediaCache = MediaCache();
  List<AssetEntity> photos = [];
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
    _loadPhotos();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
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

      // Load photos from cache (should be instant if cached)
      final loadedPhotos = await _mediaCache.loadPhotos();

      if (mounted) {
        setState(() {
          photos = loadedPhotos;
        });
        _fadeController.forward();
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
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'This app needs access to your photos to display them. Please grant permission in settings.',
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
                _loadPhotos();
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
        title: const Text('Photos'),
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
                Icons.photo_library_outlined,
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
                'Please grant photo access permission to view your photos',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _mediaCache.clearCache();
                  _loadPhotos();
                },
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (photos.isEmpty) {
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
                'No Photos Found',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                'No photos were found on your device',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
        opacity: _fadeAnimation,
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
          ),
          itemCount: photos.length,
          itemBuilder: (context, index) {
            return PhotoThumbnail(asset: photos[index]);
          },
        ),
    );
  }
}

class PhotoThumbnail extends StatefulWidget {
  final AssetEntity asset;

  const PhotoThumbnail({super.key, required this.asset});

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> with SingleTickerProviderStateMixin {
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
        _showFullImage(context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
        ),
        child: _thumbnailData != null
            ? FadeTransition(
          opacity: _animation,
          child: Image.memory(
            _thumbnailData!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        )
            : Container(
          color: Colors.grey[300],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => FullImageView(asset: widget.asset),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}
