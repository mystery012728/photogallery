import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photogallery/Pages/video_player_page.dart';
import 'dart:typed_data';

import 'package:photogallery/backend/media_cache.dart';

class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> with TickerProviderStateMixin {
  final MediaCache _mediaCache = MediaCache();
  List<AssetEntity> videos = [];
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
    _loadVideos();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos() async {
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

      // Load videos from cache (should be instant if cached)
      final loadedVideos = await _mediaCache.loadVideos();

      if (mounted) {
        setState(() {
          videos = loadedVideos;
        });
        _fadeController.forward();
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
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'This app needs access to your videos to display them. Please grant permission in settings.',
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
                _loadVideos();
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
        title: const Text('Videos'),
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
                Icons.video_library_outlined,
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
                'Please grant photo access permission to view your videos',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _mediaCache.clearCache();
                  _loadVideos();
                },
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (videos.isEmpty) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 80,
                color: Colors.grey,
              ),
              SizedBox(height: 20),
              Text(
                'No Videos Found',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                'No videos were found on your device',
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
          itemCount: videos.length,
          itemBuilder: (context, index) {
            return VideoThumbnail(asset: videos[index]);
          },
        ),
    );
  }
}

class VideoThumbnail extends StatefulWidget {
  final AssetEntity asset;

  const VideoThumbnail({super.key, required this.asset});

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> with SingleTickerProviderStateMixin {
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
      final data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(300, 200));
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
        _playVideo(context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
        ),
        child: _thumbnailData != null
            ? FadeTransition(
          opacity: _animation,
          child: ClipRRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  _thumbnailData!,
                  fit: BoxFit.cover,
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
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      _formatDuration(widget.asset.videoDuration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

  void _playVideo(BuildContext context) async {
    try {
      // Pre-validate video file access
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
            pageBuilder: (context, animation, secondaryAnimation) => VideoPlayerPage(asset: widget.asset),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
