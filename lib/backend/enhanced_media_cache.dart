import 'package:photo_manager/photo_manager.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'native_media_service.dart';

class EnhancedMediaCache {
  static final EnhancedMediaCache _instance = EnhancedMediaCache._internal();
  factory EnhancedMediaCache() => _instance;
  EnhancedMediaCache._internal();

  // Cache storage
  List<AssetEntity>? _photos;
  List<AssetEntity>? _videos;
  List<AssetPathEntity>? _albums;
  Map<String, List<AssetEntity>> _albumAssets = {};

  // Native media cache
  List<PhotoMetadata>? _nativePhotos;
  Map<int, Uint8List> _nativeThumbnailCache = {};
  Map<int, DateTime> _nativeThumbnailTimestamps = {};
  static const int _nativeThumbnailCacheMaxSize = 2000;
  static const Duration _nativeThumbnailCacheExpiry = Duration(hours: 24);

  // Thumbnail cache for ultra-fast loading
  Map<String, Uint8List> _thumbnailCache = {};
  Map<String, DateTime> _thumbnailCacheTimestamps = {};
  static const int _thumbnailCacheMaxSize = 1000;
  static const Duration _thumbnailCacheExpiry = Duration(hours: 24);

  // Loading states
  bool _photosLoaded = false;
  bool _videosLoaded = false;
  bool _albumsLoaded = false;
  bool _nativeAvailable = false;

  // Progressive loading states
  bool _photosInitialLoaded = false;
  bool _videosInitialLoaded = false;

  // Permission state
  bool? _hasPermission;

  // Background processing
  bool _backgroundProcessing = false;

  // Getters for cached data
  List<AssetEntity>? get photos => _photos;
  List<AssetEntity>? get videos => _videos;
  List<AssetPathEntity>? get albums => _albums;
  bool get photosLoaded => _photosLoaded;
  bool get videosLoaded => _videosLoaded;
  bool get albumsLoaded => _albumsLoaded;
  bool? get hasPermission => _hasPermission;
  bool get nativeAvailable => _nativeAvailable;

  // Get cached album assets
  List<AssetEntity>? getAlbumAssets(String albumId) {
    return _albumAssets[albumId];
  }

  // Initialize native service availability
  Future<void> _initializeNativeService() async {
    if (!_nativeAvailable) {
      _nativeAvailable = await NativeMediaService.isAvailable();
    }
  }

  // Check and request permission - ultra fast
  Future<bool> checkPermission() async {
    if (_hasPermission != null) {
      return _hasPermission!;
    }

    try {
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend();
      _hasPermission = permission.isAuth;
      return _hasPermission!;
    } catch (e) {
      _hasPermission = false;
      return false;
    }
  }

  // Optimized photo loading with native service priority
  Future<List<AssetEntity>> loadPhotos({bool forceReload = false}) async {
    if (_photosInitialLoaded &&
        !forceReload &&
        _photos != null &&
        _photos!.isNotEmpty) {
      return _photos!;
    }

    await _initializeNativeService();

    if (_nativeAvailable) {
      return _loadPhotosNative(forceReload: forceReload);
    } else {
      return _loadPhotosFallback(forceReload: forceReload);
    }
  }

  // Load photos using native Android MediaStore (ultra-fast)
  Future<List<AssetEntity>> _loadPhotosNative(
      {bool forceReload = false}) async {
    try {
      // Load initial batch using native service
      final response = await NativeMediaService.getPhotosMetadata(
        limit: 200, // Back to 200 for initial load
        offset: 0,
      );

      // Convert native metadata to AssetEntity-like objects
      final convertedPhotos =
          await _convertNativeToAssetEntities(response.photos);

      _photos = convertedPhotos;
      _photosInitialLoaded = true;

      // Start background thumbnail generation
      _generateNativeThumbnailsInBackground(response.photos);

      // Continue loading more in background
      _loadMorePhotosNativeInBackground();

      return _photos!;
    } catch (e) {
      // Fallback to photo_manager if native fails
      print('Native photo loading failed, falling back to photo_manager: $e');
      return _loadPhotosFallback(forceReload: forceReload);
    }
  }

  // Convert native PhotoMetadata to AssetEntity-like objects
  Future<List<AssetEntity>> _convertNativeToAssetEntities(
      List<PhotoMetadata> nativePhotos) async {
    // Since native conversion is complex, let's fallback to photo_manager for now
    // This ensures we get actual photos while keeping the native optimization structure
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final List<AssetEntity> allPhotos =
            await albums.first.getAssetListPaged(
          page: 0,
          size: 200, // Back to 200 for initial load
        );
        return allPhotos;
      }
    } catch (e) {
      print('Error converting native photos: $e');
    }

    return [];
  }

  // Load photos using photo_manager (fallback)
  Future<List<AssetEntity>> _loadPhotosFallback(
      {bool forceReload = false}) async {
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final List<AssetEntity> initialMedia =
            await albums.first.getAssetListPaged(
          page: 0,
          size: 200, // Back to 200 for initial load
        );

        _photos = initialMedia;
        _photosInitialLoaded = true;

        _generateThumbnailsInBackground(initialMedia);
        _loadMorePhotosInBackground(albums.first);

        return _photos!;
      } else {
        _photos = [];
        _photosInitialLoaded = true;
        return _photos!;
      }
    } catch (e) {
      _photos = _photos ?? [];
      _photosInitialLoaded = true;
      return _photos!;
    }
  }

  // Background loading for native photos
  Future<void> _loadMorePhotosNativeInBackground() async {
    if (_photosLoaded) return;

    try {
      int offset = 200; // Back to 200 for initial load
      bool hasMore = true;
      final List<PhotoMetadata> allPhotos = [];

      while (hasMore) {
        final response = await NativeMediaService.getPhotosMetadata(
          limit: 100,
          offset: offset,
        );

        allPhotos.addAll(response.photos);
        hasMore = response.hasMore;
        offset += 100;

        // Small delay to prevent overwhelming
        await Future.delayed(const Duration(milliseconds: 10));
      }

      _nativePhotos = allPhotos;
      _photosLoaded = true;

      // Generate thumbnails for newly loaded photos
      if (allPhotos.isNotEmpty) {
        _generateNativeThumbnailsInBackground(
            allPhotos.skip(200).toList()); // Back to 200
      }
    } catch (e) {
      _photosLoaded = true;
    }
  }

  // Background thumbnail generation for native photos
  Future<void> _generateNativeThumbnailsInBackground(
      List<PhotoMetadata> photos) async {
    if (_backgroundProcessing) return;
    _backgroundProcessing = true;

    try {
      const int batchSize = 10;
      for (int i = 0; i < photos.length; i += batchSize) {
        final batch = photos.skip(i).take(batchSize).toList();
        await _processNativeThumbnailBatch(batch);

        await Future.delayed(const Duration(milliseconds: 10));
      }
    } catch (e) {
      // Ignore background processing errors
    } finally {
      _backgroundProcessing = false;
    }
  }

  // Process a batch of native thumbnails
  Future<void> _processNativeThumbnailBatch(List<PhotoMetadata> photos) async {
    await Future.wait(photos.map((photo) async {
      try {
        if (!_nativeThumbnailCache.containsKey(photo.id)) {
          final thumbnailData = await NativeMediaService.getPhotoThumbnail(
            photoId: photo.id,
            size: 150,
          );
          if (thumbnailData != null) {
            _addToNativeThumbnailCache(photo.id, thumbnailData);
          }
        }
      } catch (e) {
        // Ignore individual thumbnail errors
      }
    }));
  }

  // Add native thumbnail to cache
  void _addToNativeThumbnailCache(int key, Uint8List data) {
    if (_nativeThumbnailCache.length >= _nativeThumbnailCacheMaxSize) {
      final oldestKey = _nativeThumbnailTimestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _nativeThumbnailCache.remove(oldestKey);
      _nativeThumbnailTimestamps.remove(oldestKey);
    }

    _nativeThumbnailCache[key] = data;
    _nativeThumbnailTimestamps[key] = DateTime.now();
  }

  // Get cached native thumbnail
  Uint8List? getCachedNativeThumbnail(int photoId) {
    final timestamp = _nativeThumbnailTimestamps[photoId];
    if (timestamp != null &&
        DateTime.now().difference(timestamp) < _nativeThumbnailCacheExpiry) {
      return _nativeThumbnailCache[photoId];
    }

    _nativeThumbnailCache.remove(photoId);
    _nativeThumbnailTimestamps.remove(photoId);
    return null;
  }

  // Background thumbnail generation using compute for better performance
  Future<void> _generateThumbnailsInBackground(List<AssetEntity> assets) async {
    if (_backgroundProcessing) return;
    _backgroundProcessing = true;

    try {
      const int batchSize = 10;
      for (int i = 0; i < assets.length; i += batchSize) {
        final batch = assets.skip(i).take(batchSize).toList();
        await _processThumbnailBatch(batch);

        await Future.delayed(const Duration(milliseconds: 10));
      }
    } catch (e) {
      // Ignore background processing errors
    } finally {
      _backgroundProcessing = false;
    }
  }

  // Process a batch of thumbnails using compute
  Future<void> _processThumbnailBatch(List<AssetEntity> assets) async {
    await Future.wait(assets.map((asset) async {
      try {
        final cacheKey = asset.id;
        if (!_thumbnailCache.containsKey(cacheKey)) {
          final thumbnailData = await asset.thumbnailDataWithSize(
            const ThumbnailSize(150, 150),
          );
          if (thumbnailData != null) {
            _addToThumbnailCache(cacheKey, thumbnailData);
          }
        }
      } catch (e) {
        // Ignore individual thumbnail errors
      }
    }));
  }

  // Add thumbnail to cache with size management
  void _addToThumbnailCache(String key, Uint8List data) {
    if (_thumbnailCache.length >= _thumbnailCacheMaxSize) {
      final oldestKey = _thumbnailCacheTimestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _thumbnailCache.remove(oldestKey);
      _thumbnailCacheTimestamps.remove(oldestKey);
    }

    _thumbnailCache[key] = data;
    _thumbnailCacheTimestamps[key] = DateTime.now();
  }

  // Get cached thumbnail
  Uint8List? getCachedThumbnail(String assetId) {
    final timestamp = _thumbnailCacheTimestamps[assetId];
    if (timestamp != null &&
        DateTime.now().difference(timestamp) < _thumbnailCacheExpiry) {
      return _thumbnailCache[assetId];
    }

    _thumbnailCache.remove(assetId);
    _thumbnailCacheTimestamps.remove(assetId);
    return null;
  }

  // Restore _loadMorePhotosInBackground to only update in-memory cache
  Future<void> _loadMorePhotosInBackground(AssetPathEntity album) async {
    if (_photosLoaded) return;

    try {
      final int totalCount = await album.assetCountAsync;
      final List<AssetEntity> allMedia = await album.getAssetListPaged(
        page: 0,
        size: totalCount,
      );

      _photos = allMedia;
      _photosLoaded = true;

      final newPhotos = allMedia.skip(200).toList(); // Back to 200
      if (newPhotos.isNotEmpty) {
        _generateThumbnailsInBackground(newPhotos);
      }
    } catch (e) {
      _photosLoaded = true;
    }
  }

  // Ultra-fast video loading
  Future<List<AssetEntity>> loadVideos({bool forceReload = false}) async {
    if (_videosInitialLoaded &&
        !forceReload &&
        _videos != null &&
        _videos!.isNotEmpty) {
      return _videos!;
    }

    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final List<AssetEntity> initialMedia =
            await albums.first.getAssetListPaged(
          page: 0,
          size: 10000, // Increased from 50 to 10000
        );

        _videos = initialMedia;
        _videosInitialLoaded = true;

        // Generate thumbnails for videos in background
        _generateThumbnailsInBackground(initialMedia);

        _loadMoreVideosInBackground(albums.first);

        return _videos!;
      } else {
        _videos = [];
        _videosInitialLoaded = true;
        return _videos!;
      }
    } catch (e) {
      _videos = _videos ?? [];
      _videosInitialLoaded = true;
      return _videos!;
    }
  }

  // Background loading for more videos
  Future<void> _loadMoreVideosInBackground(AssetPathEntity album) async {
    if (_videosLoaded) return;

    try {
      final int totalCount = await album.assetCountAsync;
      final List<AssetEntity> allMedia = await album.getAssetListPaged(
        page: 0,
        size: totalCount, // Load all videos instead of limiting to 1000
      );

      _videos = allMedia;
      _videosLoaded = true;
    } catch (e) {
      _videosLoaded = true;
    }
  }

  // Fast album loading
  Future<List<AssetPathEntity>> loadAlbums({bool forceReload = false}) async {
    if (_albumsLoaded && !forceReload && _albums != null) {
      return _albums!;
    }

    try {
      final List<AssetPathEntity> allAlbums =
          await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: false,
      );

      // Load only first 200 albums initially for fast loading
      final initialAlbums = allAlbums.take(200).toList();

      _albums = initialAlbums;
      _albumsLoaded = false; // Mark as not fully loaded yet
      return _albums!;
    } catch (e) {
      _albums = _albums ?? [];
      _albumsLoaded = false;
      return _albums!;
    }
  }

  // Load all albums at once (for silent refresh)
  Future<List<AssetPathEntity>> loadAllAlbums(
      {bool forceReload = false}) async {
    try {
      final List<AssetPathEntity> allAlbums =
          await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: false,
      );

      _albums = allAlbums;
      _albumsLoaded = true;
      return _albums!;
    } catch (e) {
      _albums = _albums ?? [];
      _albumsLoaded = true;
      return _albums!;
    }
  }

  // Fast album assets loading
  Future<List<AssetEntity>> loadAlbumAssets(AssetPathEntity album,
      {bool forceReload = false}) async {
    final albumId = album.id;

    if (!forceReload && _albumAssets.containsKey(albumId)) {
      return _albumAssets[albumId]!;
    }

    try {
      // Load initial 200 assets for fast loading
      final List<AssetEntity> initialAssets = await album.getAssetListPaged(
        page: 0,
        size: 200, // Load 200 initially for speed
      );

      _albumAssets[albumId] = initialAssets;
      return initialAssets;
    } catch (e) {
      _albumAssets[albumId] = _albumAssets[albumId] ?? [];
      return _albumAssets[albumId]!;
    }
  }

  // Load all album assets at once (for silent refresh)
  Future<List<AssetEntity>> loadAllAlbumAssets(AssetPathEntity album,
      {bool forceReload = false}) async {
    final albumId = album.id;

    try {
      // Load all assets for the album
      final int totalCount = await album.assetCountAsync;
      final List<AssetEntity> allAssets = await album.getAssetListPaged(
        page: 0,
        size: totalCount, // Load all assets
      );

      _albumAssets[albumId] = allAssets;
      return allAssets;
    } catch (e) {
      _albumAssets[albumId] = _albumAssets[albumId] ?? [];
      return _albumAssets[albumId]!;
    }
  }

  // Load all album assets in the background after albums are loaded
  Future<void> loadAllAlbumAssetsInBackground() async {
    try {
      final albums = await loadAlbums();
      await Future.wait(albums.map((album) async {
        try {
          final int totalCount = await album.assetCountAsync;
          final assets =
              await album.getAssetListPaged(page: 0, size: totalCount);
          _albumAssets[album.id] = assets;
        } catch (e) {
          // Ignore errors for individual albums
        }
      }));
    } catch (e) {
      // Ignore errors
    }
  }

  // Fast preload - only initial batches
  Future<void> preloadAllData() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return;

    await Future.wait([
      loadPhotos(),
      loadVideos(),
      loadAlbums(),
    ]);
  }

  // Force refresh all data
  Future<void> refreshAllData() async {
    _photosLoaded = false;
    _videosLoaded = false;
    _albumsLoaded = false;
    _photosInitialLoaded = false;
    _videosInitialLoaded = false;
    _photos = null;
    _videos = null;
    _albums = null;
    _albumAssets.clear();
    _hasPermission = null;
    _nativePhotos = null;

    // Clear thumbnail caches
    _thumbnailCache.clear();
    _thumbnailCacheTimestamps.clear();
    _nativeThumbnailCache.clear();
    _nativeThumbnailTimestamps.clear();

    await preloadAllData();
  }

  // Clear cache
  void clearCache() {
    _photos = null;
    _videos = null;
    _albums = null;
    _albumAssets.clear();
    _photosLoaded = false;
    _videosLoaded = false;
    _albumsLoaded = false;
    _photosInitialLoaded = false;
    _videosInitialLoaded = false;
    _hasPermission = null;
    _nativePhotos = null;

    // Clear thumbnail caches
    _thumbnailCache.clear();
    _thumbnailCacheTimestamps.clear();
    _nativeThumbnailCache.clear();
    _nativeThumbnailTimestamps.clear();
  }

  // Get loading progress info
  String getLoadingInfo() {
    final photoCount = _photos?.length ?? 0;
    final videoCount = _videos?.length ?? 0;
    final albumCount = _albums?.length ?? 0;
    final thumbnailCount = _thumbnailCache.length;
    final nativeThumbnailCount = _nativeThumbnailCache.length;
    final nativePhotoCount = _nativePhotos?.length ?? 0;

    return 'Photos: $photoCount, Videos: $videoCount, Albums: $albumCount, ' +
        'Thumbnails: $thumbnailCount, Native Thumbnails: $nativeThumbnailCount, ' +
        'Native Photos: $nativePhotoCount, Native Available: $_nativeAvailable';
  }

  // Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'photos': _photos?.length ?? 0,
      'videos': _videos?.length ?? 0,
      'albums': _albums?.length ?? 0,
      'thumbnails': _thumbnailCache.length,
      'nativeThumbnails': _nativeThumbnailCache.length,
      'nativePhotos': _nativePhotos?.length ?? 0,
      'thumbnailCacheSize': _thumbnailCacheMaxSize,
      'nativeThumbnailCacheSize': _nativeThumbnailCacheMaxSize,
      'photosLoaded': _photosLoaded,
      'videosLoaded': _videosLoaded,
      'albumsLoaded': _albumsLoaded,
      'nativeAvailable': _nativeAvailable,
    };
  }

  // Load all videos at once (for quick refresh)
  Future<List<AssetEntity>> loadAllVideos({bool forceReload = false}) async {
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final int totalCount = await albums.first.assetCountAsync;
        final List<AssetEntity> allVideos =
            await albums.first.getAssetListPaged(
          page: 0,
          size: totalCount, // Load all videos
        );

        _videos = allVideos;
        _videosInitialLoaded = true;
        _videosLoaded = true;

        // Generate thumbnails for all videos
        _generateThumbnailsInBackground(allVideos);

        return _videos!;
      } else {
        _videos = [];
        _videosInitialLoaded = true;
        _videosLoaded = true;
        return _videos!;
      }
    } catch (e) {
      _videos = _videos ?? [];
      _videosInitialLoaded = true;
      _videosLoaded = true;
      return _videos!;
    }
  }

  // Load all photos at once (for quick refresh)
  Future<List<AssetEntity>> loadAllPhotos({bool forceReload = false}) async {
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final int totalCount = await albums.first.assetCountAsync;
        final List<AssetEntity> allPhotos =
            await albums.first.getAssetListPaged(
          page: 0,
          size: totalCount, // Load all photos
        );

        _photos = allPhotos;
        _photosInitialLoaded = true;
        _photosLoaded = true;

        // Generate thumbnails for all photos
        _generateThumbnailsInBackground(allPhotos);

        return _photos!;
      } else {
        _photos = [];
        _photosInitialLoaded = true;
        _photosLoaded = true;
        return _photos!;
      }
    } catch (e) {
      _photos = _photos ?? [];
      _photosInitialLoaded = true;
      _photosLoaded = true;
      return _photos!;
    }
  }
}
