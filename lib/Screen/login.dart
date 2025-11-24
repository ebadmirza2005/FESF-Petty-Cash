import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project/Screen/bill_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isLoading = false;
  bool passwordVisible = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _emailCtrl.text = prefs.getString('saved_email') ?? '';
    _passCtrl.text = prefs.getString('saved_password') ?? '';
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse("https://stage-cash.fesf-it.com/api/login"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailCtrl.text.trim(),
          'password': _passCtrl.text.trim(),
        }),
      );

      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['data'] != null) {
        final data = body['data'];
        final user = data['user'];

        final prefs = await SharedPreferences.getInstance();
        prefs
          ..setString("name", user['name'])
          ..setString("email", user['email'])
          ..setString('auth_token', data['token'])
          ..setString('locationCode', user['location']['code'])
          ..setInt('user_id', user['id'])
          ..setInt('location_id', user['location']['id'])
          ..setString('location_name', user['location']['name']);

        if (!mounted) return;
        await Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => BillScreen(
              name: user['name'],
              locationCode: user['location']['code'],
            ),
          ),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage = "Invalid email or password";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Invalid email or password";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputStyle(String label) => InputDecoration(
    labelText: label,
    hintText: 'Enter Your $label',
    border: const OutlineInputBorder(),
    suffixIcon: label == "Password"
        ? IconButton(
            icon: Icon(
              passwordVisible ? Icons.visibility_off : Icons.visibility,
              color: Colors.blue,
            ),
            onPressed: () {
              setState(() {
                passwordVisible = !passwordVisible;
              });
            },
          )
        : null,
  );

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Container
            Container(
              height: screenHeight * 0.3,
              child: Container(
                width: double.infinity,
                height: screenHeight * 0.27,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    bottomRight: Radius.circular(100),
                    bottomLeft: Radius.circular(100),
                  ),
                ),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      // border: Border.all(color: Colors.blue.shade800, width: 5),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Image.asset(
                      'assets/FESF.png',
                      color: const Color(0xff036a84),
                      width: screenWidth * 0.7,
                      height: screenWidth * 0.7,
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: screenHeight * 0.04),

            const Text(
              "Welcome",
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Color(0xff1c1c1c),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Sign in to continue",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: screenHeight * 0.03),

            if (_errorMessage != null)
              Container(
                padding: EdgeInsets.symmetric(
                  vertical: screenHeight * 0.012,
                  horizontal: screenWidth * 0.04,
                ),
                margin: EdgeInsets.only(bottom: screenHeight * 0.02),
                decoration: BoxDecoration(
                  color: const Color(0xfff8d6d6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: screenWidth * 0.04,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Email Field
                  SizedBox(
                    width: screenWidth * 0.85,
                    child: TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'Enter Your Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return "Email is required";
                        final regex = RegExp(
                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                        );
                        return regex.hasMatch(v)
                            ? null
                            : "Enter a valid email address";
                      },
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.025),

                  // Password Field
                  SizedBox(
                    width: screenWidth * 0.85,
                    child: TextFormField(
                      controller: _passCtrl,
                      obscureText: passwordVisible,
                      decoration: _inputStyle('Password'),
                      validator: (v) => (v == null || v.isEmpty)
                          ? "Password is required!"
                          : null,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.04),

                  // Login Button
                  SizedBox(
                    width: screenWidth * 0.85,
                    height: screenHeight * 0.065,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            )
                          : const Text(
                              "Login",
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.05),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
