import 'dart:io';
// import 'dart:ui' as ui;
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
  Rect _cropRect = const Rect.fromLTWH(50, 50, 200, 200);
  Offset? _dragStart;
  bool _isDragging = false;

  final GlobalKey _imageKey = GlobalKey();

  bool _isCropped = false; // NEW: crop confirm hone ka flag
  String? _croppedPath; // NEW: cropped image ka path

  Future<void> _cropImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
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

    setState(() {
      _isCropped = true; // crop complete
      _croppedPath = newPath;
    });

    Navigator.pop(
      context,
      newPath,
    ); // ya agar preview me dikhana ho to ye line comment karein
  }

  // ... baaki GestureDetector aur crop logic same ...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text("Image Crop"),
        backgroundColor: Colors.blue,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: IconButton(
              onPressed: _cropImage,
              icon: const Icon(Icons.check),
            ),
          ),
        ],
      ),
      body: Center(
        child: _isCropped
            ? Container(
                // Agar crop ho gaya to sirf cropped image show karein
                child: Image.file(File(_croppedPath!)),
              )
            : LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  onPanStart: (details) {
                    if (_cropRect.contains(details.localPosition)) {
                      _isDragging = true;
                      _dragStart = details.localPosition;
                    } else {
                      setState(() {
                        _cropRect = Rect.fromLTWH(
                          details.localPosition.dx,
                          details.localPosition.dy,
                          0,
                          0,
                        );
                      });
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
                    } else {
                      double newWidth =
                          (details.localPosition.dx - _cropRect.left).clamp(
                            50,
                            constraints.maxWidth - _cropRect.left,
                          );
                      double newHeight =
                          (details.localPosition.dy - _cropRect.top).clamp(
                            50,
                            constraints.maxHeight - _cropRect.top,
                          );

                      setState(() {
                        _cropRect = Rect.fromLTWH(
                          _cropRect.left,
                          _cropRect.top,
                          newWidth,
                          newHeight,
                        );
                      });
                    }
                  },
                  onPanEnd: (details) {
                    _isDragging = false;
                  },
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        key: _imageKey,
                        minScale: 1,
                        maxScale: 5,
                        panEnabled: true,
                        scaleEnabled: true,
                        child: Image.file(
                          File(widget.imagePath),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Crop rectangle
                      Positioned(
                        left: _cropRect.left,
                        top: _cropRect.top,
                        child: Container(
                          width: _cropRect.width,
                          height: _cropRect.height,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                      // Resize handle
                      Positioned(
                        left: _cropRect.right - 10,
                        top: _cropRect.bottom - 10,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newWidth =
                                  (_cropRect.width + details.delta.dx).clamp(
                                    50,
                                    constraints.maxWidth - _cropRect.left,
                                  );
                              double newHeight =
                                  (_cropRect.height + details.delta.dy).clamp(
                                    50,
                                    constraints.maxHeight - _cropRect.top,
                                  );

                              _cropRect = Rect.fromLTWH(
                                _cropRect.left,
                                _cropRect.top,
                                newWidth,
                                newHeight,
                              );
                            });
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(10),
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
