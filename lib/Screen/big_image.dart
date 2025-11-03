import 'dart:io';
import 'package:flutter/material.dart';

class BigImage extends StatefulWidget {
  final File imageFile;

  const BigImage({super.key, required this.imageFile});

  @override
  State<BigImage> createState() => _BigImageState();
}

class _BigImageState extends State<BigImage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Bill Image'),
      ),
      body: Center(
        child: Hero(
          tag: 'billImageHero',
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(widget.imageFile),
          ),
        ),
      ),
    );
  }
}
