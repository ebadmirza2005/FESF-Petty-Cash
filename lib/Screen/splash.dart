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

class _SplashState extends State<Splash> {
  @override
  
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');
    String? name = prefs.getString('name');
    String? locationCode = prefs.getString('locationCode');

    // for splash delay
    await Future.delayed(const Duration(seconds: 3));

    if (token != null && token.isNotEmpty) {
      // user already logged in
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BillScreen(
            name: name ?? '',
            locationCode: locationCode ?? '',
          ),
        ),
      );
    } else {
      // user not login
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.blue,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(75),
                  image: const DecorationImage(
                    image: AssetImage("assets/FESF.png"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "WELCOME TO FESF BILL APP",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
