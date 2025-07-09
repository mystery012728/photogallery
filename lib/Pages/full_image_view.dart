import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';

class FullImageView extends StatelessWidget {
  final AssetEntity asset;

  const FullImageView({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          asset.title ?? 'Image',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => _showImageInfo(context),
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<Uint8List?>(
          future: asset.originBytes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
              return InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                ),
              );
            }
            return Container();
          },
        ),
      ),
    );
  }

  void _showImageInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Image Information'),
          content: FutureBuilder<String>(
            future: _getImageInfo(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Text(snapshot.data!);
              }
              return Container();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _getImageInfo() async {
    final file = await asset.file;
    final fileSize = file != null ? await file.length() : 0;
    final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);

    return '''
Title: ${asset.title ?? 'Unknown'}
Size: ${asset.width} x ${asset.height}
File Size: ${sizeInMB} MB
Date: ${asset.createDateTime.toString().split('.')[0]}
Type: ${asset.mimeType ?? 'Unknown'}
''';
  }
}
