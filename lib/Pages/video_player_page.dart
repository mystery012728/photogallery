import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';

class VideoPlayerPage extends StatefulWidget {
  final AssetEntity asset;
  const VideoPlayerPage({super.key, required this.asset});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final file = await widget.asset.file;
      if (file == null || !await file.exists()) return;

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      _controller!.addListener(() => setState(() => _isPlaying = _controller!.value.isPlaying));

      if (mounted) {
        setState(() {});
        await _controller!.play();
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  Future<void> _togglePlayPause() async {
    if (_controller?.value.isInitialized != true) return;
    _controller!.value.isPlaying ? await _controller!.pause() : await _controller!.play();
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);

    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final twoDigits = (int n) => n.toString().padLeft(2, '0');

    return hours > 0
        ? '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}'
        : '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _showVideoInfo() {
    if (_controller == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Video Information'),
          ],
        ),
        content: FutureBuilder<String>(
          future: _getVideoInfo(),
          builder: (context, snapshot) => snapshot.hasData
              ? SingleChildScrollView(child: Text(snapshot.data!))
              : const CircularProgressIndicator(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<String> _getVideoInfo() async {
    final file = await widget.asset.file;
    final fileSize = file != null ? await file.length() : 0;
    final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);

    return ''' 
   Title: ${widget.asset.title ?? 'Unknown'}
   Duration: ${_formatDuration(_controller!.value.duration)}
   Size: ${_controller!.value.size.width.toInt()} × ${_controller!.value.size.height.toInt()}
   File Size: ${sizeInMB} MB
   Aspect Ratio: ${_controller!.value.aspectRatio.toStringAsFixed(2)}
   Date: ${widget.asset.createDateTime.toString().split('.')[0]}
   Type: ${widget.asset.mimeType ?? 'Unknown'}''';
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.asset.title ?? 'Video',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_controller?.value.isInitialized == true)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Video Info',
              onPressed: _showVideoInfo,
            ),
        ],
      ),
      body: _controller?.value.isInitialized == true
          ? GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
            if (_showControls) _buildControls(),
          ],
        ),
      )
          : const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.7),
          ],
        ),
      ),
      child: Column(
        children: [
          // Top controls
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    tooltip: _isFullScreen ? 'Exit Fullscreen' : 'Fullscreen',
                    onPressed: _toggleFullScreen,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Center play/pause button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              iconSize: 64,
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: _togglePlayPause,
            ),
          ),
          const Spacer(),
          // Bottom controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Progress bar
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.redAccent,
                      bufferedColor: Colors.white30,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Time display
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: _controller!,
                      builder: (context, value, child) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatDuration(value.position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatDuration(_controller!.value.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}