import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project/Screen/bill_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UploadLoading extends StatefulWidget {
  final String name;
  final String locationCode;
  final File? imageFile;
  final Map<String, dynamic>? billData;

  const UploadLoading({
    super.key,
    required this.name,
    required this.locationCode,
    this.imageFile,
    this.billData,
  });

  @override
  State<UploadLoading> createState() => _UploadLoadingState();
}

class _UploadLoadingState extends State<UploadLoading> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FutureBuilder(
          future: Future.delayed(const Duration(seconds: 3)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    "Uploading",
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 30),
                  CircularProgressIndicator(color: Colors.blue, strokeWidth: 6),
                ],
              );
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('reporting_period');

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BillScreen(
                      name: widget.name,
                      locationCode: widget.locationCode,
                      billData: widget.billData,
                      imageFile: widget.imageFile,
                    ),
                  ),
                  (route) => false,
                );
              });
              return Container();
            }
          },
        ),
      ),
    );
  }
}
