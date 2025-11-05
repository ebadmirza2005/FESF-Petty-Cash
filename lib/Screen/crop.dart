import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CroppedImage extends StatefulWidget {
  final String imagePath;
  const CroppedImage({super.key, required this.imagePath});

  @override
  State<CroppedImage> createState() => _CroppedImageState();
}

class _CroppedImageState extends State<CroppedImage> {
  Rect? _cropRect;
  late double _startX, _startY, _endX, _endY;
  final GlobalKey _imageKey = GlobalKey();

  Future<void> _cropAndReturn() async {
    if (_cropRect == null) {
      Navigator.pop(context, widget.imagePath);
      return;
    }

    // Load image bytes
    final bytes = await File(widget.imagePath).readAsBytes();
    final original = img.decodeImage(bytes)!;

    final renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;

    // Calculate crop ratio
    final scaleX = original.width / size.width;
    final scaleY = original.height / size.height;

    final cropX = (_cropRect!.left * scaleX).round();
    final cropY = (_cropRect!.top * scaleY).round();
    final cropW = (_cropRect!.width * scaleX).round();
    final cropH = (_cropRect!.height * scaleY).round();

    // Safe crop
    final cropped = img.copyCrop(
      original,
      x: cropX.clamp(0, original.width - 1),
      y: cropY.clamp(0, original.height - 1),
      width: cropW.clamp(1, original.width - cropX),
      height: cropH.clamp(1, original.height - cropY),
    );

    // Save cropped image
    final dir = await getTemporaryDirectory();
    final newPath = path.join(
      dir.path,
      'cropped_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await File(newPath).writeAsBytes(img.encodePng(cropped));

    Navigator.pop(context, newPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Crop Image"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _cropAndReturn,
            child: const Text(
              "Done",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: Image.file(
                  File(widget.imagePath),
                  key: _imageKey,
                  fit: BoxFit.contain,
                ),
              ),
              if (_cropRect != null)
                Positioned(
                  left: _cropRect!.left,
                  top: _cropRect!.top,
                  child: Container(
                    width: _cropRect!.width,
                    height: _cropRect!.height,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                  ),
                ),
              GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _startX = details.localPosition.dx;
                    _startY = details.localPosition.dy;
                    _endX = _startX;
                    _endY = _startY;
                    _cropRect = Rect.fromPoints(
                      Offset(_startX, _startY),
                      Offset(_endX, _endY),
                    );
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _endX = details.localPosition.dx;
                    _endY = details.localPosition.dy;
                    _cropRect = Rect.fromPoints(
                      Offset(_startX, _startY),
                      Offset(_endX, _endY),
                    );
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
