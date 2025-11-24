import 'dart:async';
import 'package:flutter/material.dart';
import 'package:project/Screen/bill_screen.dart';
import 'package:project/Screen/login.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();

    _startSplash();
  }

  Future<void> _startSplash() async {
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final name = prefs.getString('name');
    final locationCode = prefs.getString('locationCode');

    if (token != null && token.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BillScreen(name: name ?? '', locationCode: locationCode ?? ''),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double imageSize = screenWidth * 0.4;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 5),
                borderRadius: BorderRadius.circular(imageSize),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/FESF.png',
                  height: imageSize,
                  width: imageSize,
                  fit: BoxFit.cover,
                  color: Color(0xff036a84),
                ),
              ),
            ),
            SizedBox(height: 40),
            Text(
              "FESF BILL APP",
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
