import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';

// Photo metadata structure
class PhotoMetadata {
  final int id;
  final String name;
  final String path;
  final int dateAdded;
  final int dateModified;
  final int size;
  final int width;
  final int height;
  final String mimeType;

  PhotoMetadata({
    required this.id,
    required this.name,
    required this.path,
    required this.dateAdded,
    required this.dateModified,
    required this.size,
    required this.width,
    required this.height,
    required this.mimeType,
  });

  factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      id: json['id'] as int,
      name: json['name'] as String,
      path: json['path'] as String,
      dateAdded: json['dateAdded'] as int,
      dateModified: json['dateModified'] as int,
      size: json['size'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      mimeType: json['mimeType'] as String,
    );
  }

  DateTime get createDateTime =>
      DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000);
  DateTime get modifiedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(dateModified * 1000);
}

// Response structure for photo metadata
class PhotosResponse {
  final List<PhotoMetadata> photos;
  final int count;
  final bool hasMore;

  PhotosResponse({
    required this.photos,
    required this.count,
    required this.hasMore,
  });

  factory PhotosResponse.fromJson(Map<String, dynamic> json) {
    final photosList = json['photos'] as List;
    final photos =
        photosList.map((photo) => PhotoMetadata.fromJson(photo)).toList();

    return PhotosResponse(
      photos: photos,
      count: json['count'] as int,
      hasMore: json['hasMore'] as bool,
    );
  }
}

/// Simple semaphore implementation for controlling concurrent operations
class Semaphore {
  final int _maxCount;
  int _currentCount;

  Semaphore(this._maxCount) : _currentCount = _maxCount;

  Future<void> acquire() async {
    while (_currentCount <= 0) {
      await Future.delayed(const Duration(milliseconds: 1));
    }
    _currentCount--;
  }

  void release() {
    if (_currentCount < _maxCount) {
      _currentCount++;
    }
  }
}

class NativeMediaService {
  static const MethodChannel _channel =
      MethodChannel('com.example.photogallery/native_media');

  /// Get photos metadata using native Android MediaStore
  /// This is much faster than using photo_manager for large galleries
  static Future<PhotosResponse> getPhotosMetadata({
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod('getPhotosMetadata', {
        'limit': limit,
        'offset': offset,
      });

      final jsonResult = json.decode(result as String);
      return PhotosResponse.fromJson(jsonResult);
    } on PlatformException catch (e) {
      throw Exception('Failed to get photos metadata: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error getting photos metadata: $e');
    }
  }

  /// Get photo thumbnail using native Android MediaStore
  /// This provides better performance than photo_manager thumbnails
  static Future<Uint8List?> getPhotoThumbnail({
    required int photoId,
    int size = 150,
  }) async {
    try {
      final result = await _channel.invokeMethod('getPhotoThumbnail', {
        'photoId': photoId,
        'size': size,
      });

      if (result != null) {
        return Uint8List.fromList(List<int>.from(result));
      }
      return null;
    } on PlatformException catch (e) {
      // Log error but don't throw - fallback to photo_manager
      print('Native thumbnail failed for photo $photoId: ${e.message}');
      return null;
    } catch (e) {
      print('Unexpected error getting native thumbnail: $e');
      return null;
    }
  }

  /// Get total photos count using native Android MediaStore
  static Future<int> getPhotosCount() async {
    try {
      final result = await _channel.invokeMethod('getPhotosCount');
      return result as int;
    } on PlatformException catch (e) {
      throw Exception('Failed to get photos count: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error getting photos count: $e');
    }
  }

  /// Check if native media service is available
  static Future<bool> isAvailable() async {
    try {
      await _channel.invokeMethod('getPhotosCount');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get photos metadata with pagination support
  static Stream<PhotosResponse> getPhotosMetadataStream({
    int pageSize = 50,
  }) async* {
    int offset = 0;
    bool hasMore = true;

    while (hasMore) {
      try {
        final response = await getPhotosMetadata(
          limit: pageSize,
          offset: offset,
        );

        yield response;

        hasMore = response.hasMore;
        offset += pageSize;

        // Small delay to prevent overwhelming the system
        await Future.delayed(const Duration(milliseconds: 10));
      } catch (e) {
        print('Error in photos metadata stream: $e');
        break;
      }
    }
  }

  /// Preload thumbnails for a list of photo IDs
  static Future<Map<int, Uint8List>> preloadThumbnails({
    required List<int> photoIds,
    int size = 150,
    int maxConcurrent = 5,
  }) async {
    final Map<int, Uint8List> thumbnails = {};
    final semaphore = Semaphore(maxConcurrent);

    await Future.wait(
      photoIds.map((photoId) async {
        await semaphore.acquire();
        try {
          final thumbnail =
              await getPhotoThumbnail(photoId: photoId, size: size);
          if (thumbnail != null) {
            thumbnails[photoId] = thumbnail;
          }
        } finally {
          semaphore.release();
        }
      }),
    );

    return thumbnails;
  }
}
