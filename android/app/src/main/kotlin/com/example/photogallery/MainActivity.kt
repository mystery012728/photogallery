package com.example.photogallery

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentResolver
import android.provider.MediaStore
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import org.json.JSONObject
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.photogallery/native_media"
    private val TAG = "PhotoGallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPhotosMetadata" -> {
                    val limit = call.argument<Int>("limit") ?: 100
                    val offset = call.argument<Int>("offset") ?: 0
                    getPhotosMetadata(limit, offset, result)
                }
                "getPhotoThumbnail" -> {
                    val photoId = call.argument<Long>("photoId")
                    val size = call.argument<Int>("size") ?: 150
                    if (photoId != null) {
                        getPhotoThumbnail(photoId, size, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Photo ID is required", null)
                    }
                }
                "getPhotosCount" -> {
                    getPhotosCount(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getPhotosMetadata(limit: Int, offset: Int, result: MethodChannel.Result) {
        try {
            val contentResolver: ContentResolver = context.contentResolver
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
                MediaStore.Images.Media.MIME_TYPE
            )

            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
            val selection = "${MediaStore.Images.Media.DATA} IS NOT NULL"
            
            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            )

            val photosArray = JSONArray()
            var count = 0

            cursor?.use { 
                if (cursor.moveToPosition(offset)) {
                    while (cursor.moveToNext() && count < limit) {
                        val photo = JSONObject()
                        photo.put("id", cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)))
                        photo.put("name", cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)))
                        photo.put("path", cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)))
                        photo.put("dateAdded", cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)))
                        photo.put("dateModified", cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)))
                        photo.put("size", cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)))
                        photo.put("width", cursor.getInt(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)))
                        photo.put("height", cursor.getInt(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)))
                        photo.put("mimeType", cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)))
                        
                        photosArray.put(photo)
                        count++
                    }
                }
            }

            val response = JSONObject()
            response.put("photos", photosArray)
            response.put("count", count)
            response.put("hasMore", count == limit)

            result.success(response.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error getting photos metadata: ${e.message}")
            result.error("QUERY_ERROR", "Failed to get photos metadata", e.message)
        }
    }

    private fun getPhotoThumbnail(photoId: Long, size: Int, result: MethodChannel.Result) {
        try {
            val contentResolver: ContentResolver = context.contentResolver
            val uri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, photoId.toString())
            
            val bitmap = MediaStore.Images.Thumbnails.getThumbnail(
                contentResolver,
                photoId,
                MediaStore.Images.Thumbnails.MINI_KIND,
                null
            )

            if (bitmap != null) {
                // Resize bitmap to requested size
                val resizedBitmap = Bitmap.createScaledBitmap(bitmap, size, size, true)
                
                // Convert to byte array
                val stream = ByteArrayOutputStream()
                resizedBitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                val byteArray = stream.toByteArray()
                
                result.success(byteArray)
            } else {
                // Fallback: try to load full image and create thumbnail
                try {
                    val inputStream = contentResolver.openInputStream(uri)
                    val options = BitmapFactory.Options().apply {
                        inJustDecodeBounds = true
                    }
                    BitmapFactory.decodeStream(inputStream, null, options)
                    inputStream?.close()

                    // Calculate sample size
                    val sampleSize = calculateInSampleSize(options, size, size)
                    
                    val decodeOptions = BitmapFactory.Options().apply {
                        inSampleSize = sampleSize
                    }
                    
                    val fullImageStream = contentResolver.openInputStream(uri)
                    val fullBitmap = BitmapFactory.decodeStream(fullImageStream, null, decodeOptions)
                    fullImageStream?.close()

                    if (fullBitmap != null) {
                        val resizedBitmap = Bitmap.createScaledBitmap(fullBitmap, size, size, true)
                        val stream = ByteArrayOutputStream()
                        resizedBitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                        val byteArray = stream.toByteArray()
                        
                        result.success(byteArray)
                    } else {
                        result.error("THUMBNAIL_ERROR", "Failed to create thumbnail", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error creating thumbnail: ${e.message}")
                    result.error("THUMBNAIL_ERROR", "Failed to create thumbnail", e.message)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting photo thumbnail: ${e.message}")
            result.error("THUMBNAIL_ERROR", "Failed to get photo thumbnail", e.message)
        }
    }

    private fun getPhotosCount(result: MethodChannel.Result) {
        try {
            val contentResolver: ContentResolver = context.contentResolver
            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                arrayOf("COUNT(*)"),
                null,
                null,
                null
            )

            var count = 0
            cursor?.use {
                if (cursor.moveToFirst()) {
                    count = cursor.getInt(0)
                }
            }

            result.success(count)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting photos count: ${e.message}")
            result.error("COUNT_ERROR", "Failed to get photos count", e.message)
        }
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2

            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }

        return inSampleSize
    }
}
