import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class CroppedImage extends StatefulWidget {
  final File image;
  const CroppedImage({super.key, required this.image});

  @override
  State<CroppedImage> createState() => _CroppedImageState();
}

class _CroppedImageState extends State<CroppedImage> {
  Rect _cropRect = const Rect.fromLTWH(80, 150, 220, 220);
  Offset? _dragStart;
  bool _isDragging = false;

  final GlobalKey _imageKey = GlobalKey();

  Future<void> _cropImage() async {
    final bytes = await widget.image.readAsBytes();
    final original = img.decodeImage(bytes)!;

    final renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;

    final scaleX = original.width / size.width;
    final scaleY = original.height / size.height;

    final cropX = (_cropRect.left * scaleX).round();
    final cropY = (_cropRect.top * scaleY).round();
    final cropW = (_cropRect.width * scaleX).round();
    final cropH = (_cropRect.height * scaleY).round();

    final cropped = img.copyCrop(
      original,
      x: cropX.clamp(0, original.width - 1),
      y: cropY.clamp(0, original.height - 1),
      width: cropW.clamp(1, original.width - cropX),
      height: cropH.clamp(1, original.height - cropY),
    );

    final dir = await getTemporaryDirectory();
    final newPath = path.join(
      dir.path,
      'cropped_${DateTime.now().millisecondsSinceEpoch}.png',
    );

    await File(newPath).writeAsBytes(img.encodePng(cropped));
    if (mounted) Navigator.pop(context, newPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          "Crop Image",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent, size: 28),
            onPressed: _cropImage,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            onPanStart: (details) {
              if (_cropRect.contains(details.localPosition)) {
                _isDragging = true;
                _dragStart = details.localPosition;
              }
            },
            onPanUpdate: (details) {
              if (_isDragging && _dragStart != null) {
                final dx = details.localPosition.dx - _dragStart!.dx;
                final dy = details.localPosition.dy - _dragStart!.dy;

                setState(() {
                  double newLeft = (_cropRect.left + dx).clamp(
                    0.0,
                    constraints.maxWidth - _cropRect.width,
                  );
                  double newTop = (_cropRect.top + dy).clamp(
                    0.0,
                    constraints.maxHeight - _cropRect.height,
                  );
                  _cropRect = Rect.fromLTWH(
                    newLeft,
                    newTop,
                    _cropRect.width,
                    _cropRect.height,
                  );
                  _dragStart = details.localPosition;
                });
              }
            },
            onPanEnd: (_) => _isDragging = false,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Zoomable image
                InteractiveViewer(
                  key: _imageKey,
                  minScale: 1,
                  maxScale: 4,
                  child: Image.file(
                    widget.image,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),

                // Dark overlay outside crop area
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _CropOverlayPainter(_cropRect)),
                  ),
                ),

                // White border for crop area
                Positioned(
                  left: _cropRect.left,
                  top: _cropRect.top,
                  child: Container(
                    width: _cropRect.width,
                    height: _cropRect.height,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Resize handle (bottom right)
                Positioned(
                  left: _cropRect.right - 16,
                  top: _cropRect.bottom - 16,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        double newWidth = (_cropRect.width + details.delta.dx)
                            .clamp(80, constraints.maxWidth - _cropRect.left);
                        double newHeight = (_cropRect.height + details.delta.dy)
                            .clamp(80, constraints.maxHeight - _cropRect.top);
                        _cropRect = Rect.fromLTWH(
                          _cropRect.left,
                          _cropRect.top,
                          newWidth,
                          newHeight,
                        );
                      });
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        border: Border.all(color: Colors.white, width: 1.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.drag_handle,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Overlay painter for dim background
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  _CropOverlayPainter(this.cropRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.6);
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRect(cropRect),
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
