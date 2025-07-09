import 'package:photo_manager/photo_manager.dart';

class MediaCache {
  static final MediaCache _instance = MediaCache._internal();
  factory MediaCache() => _instance;
  MediaCache._internal();

  // Cache storage
  List<AssetEntity>? _photos;
  List<AssetEntity>? _videos;
  List<AssetPathEntity>? _albums;
  Map<String, List<AssetEntity>> _albumAssets = {};

  // Loading states
  bool _photosLoaded = false;
  bool _videosLoaded = false;
  bool _albumsLoaded = false;

  // Progressive loading states
  bool _photosInitialLoaded = false;
  bool _videosInitialLoaded = false;

  // Permission state
  bool? _hasPermission;

  // Getters for cached data
  List<AssetEntity>? get photos => _photos;
  List<AssetEntity>? get videos => _videos;
  List<AssetPathEntity>? get albums => _albums;
  bool get photosLoaded => _photosLoaded;
  bool get videosLoaded => _videosLoaded;
  bool get albumsLoaded => _albumsLoaded;
  bool? get hasPermission => _hasPermission;

  // Get cached album assets
  List<AssetEntity>? getAlbumAssets(String albumId) {
    return _albumAssets[albumId];
  }

  // Check and request permission - ultra fast
  Future<bool> checkPermission() async {
    if (_hasPermission != null) {
      return _hasPermission!;
    }

    try {
      final PermissionState permission = await PhotoManager.requestPermissionExtend();
      _hasPermission = permission.isAuth;
      return _hasPermission!;
    } catch (e) {
      _hasPermission = false;
      return false;
    }
  }

  // Ultra-fast photo loading - load small batch first, then continue in background
  Future<List<AssetEntity>> loadPhotos({bool forceReload = false}) async {
    if (_photosInitialLoaded && !forceReload && _photos != null && _photos!.isNotEmpty) {
      return _photos!;
    }

    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        // Load small initial batch for instant display (under 2 seconds)
        final List<AssetEntity> initialMedia = await albums.first.getAssetListPaged(
          page: 0,
          size: 200, // Small initial batch for speed
        );

        _photos = initialMedia;
        _photosInitialLoaded = true;

        // Continue loading more in background without blocking UI
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

  // Background loading for more photos
  Future<void> _loadMorePhotosInBackground(AssetPathEntity album) async {
    if (_photosLoaded) return;

    try {
      // Load more photos in chunks without blocking UI
      final List<AssetEntity> allMedia = await album.getAssetListPaged(
        page: 0,
        size: 2000, // Reasonable size for background loading
      );

      _photos = allMedia;
      _photosLoaded = true;
    } catch (e) {
      // Ignore background loading errors
      _photosLoaded = true;
    }
  }

  // Ultra-fast video loading
  Future<List<AssetEntity>> loadVideos({bool forceReload = false}) async {
    if (_videosInitialLoaded && !forceReload && _videos != null && _videos!.isNotEmpty) {
      return _videos!;
    }

    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        // Load small initial batch for instant display
        final List<AssetEntity> initialMedia = await albums.first.getAssetListPaged(
          page: 0,
          size: 100, // Even smaller for videos as they're typically fewer
        );

        _videos = initialMedia;
        _videosInitialLoaded = true;

        // Continue loading more in background
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
      final List<AssetEntity> allMedia = await album.getAssetListPaged(
        page: 0,
        size: 1000, // Reasonable size for videos
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
      final List<AssetPathEntity> allAlbums = await PhotoManager.getAssetPathList(
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
  Future<List<AssetEntity>> loadAlbumAssets(AssetPathEntity album, {bool forceReload = false}) async {
    final albumId = album.id;

    if (!forceReload && _albumAssets.containsKey(albumId)) {
      return _albumAssets[albumId]!;
    }

    try {
      // Load reasonable amount for albums
      final List<AssetEntity> assets = await album.getAssetListPaged(
        page: 0,
        size: 1000, // Reasonable size per album
      );

      _albumAssets[albumId] = assets;
      return assets;
    } catch (e) {
      _albumAssets[albumId] = _albumAssets[albumId] ?? [];
      return _albumAssets[albumId]!;
    }
  }

  // Fast preload - only initial batches
  Future<void> preloadAllData() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return;

    // Load only initial batches in parallel for speed
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

    // Reload with fast initial loading
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
  }

  // Get loading progress info
  String getLoadingInfo() {
    final photoCount = _photos?.length ?? 0;
    final videoCount = _videos?.length ?? 0;
    final albumCount = _albums?.length ?? 0;

    return 'Photos: $photoCount, Videos: $videoCount, Albums: $albumCount';
  }
}
