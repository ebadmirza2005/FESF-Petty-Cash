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
  String? _errorMessage; // 🔹 New variable for showing invalid error

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
        // 🔹 Show single error message
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
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 130,
                  child: Image.asset("assets/FESF.png"),
                ),
                const Text(
                  "Welcome",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff1c1c1c),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Sign in to continue",
                  style: TextStyle(fontSize: 18, color: Color(0xff1c1c1c)),
                ),
                const SizedBox(height: 26),

                // 🔹 Show "Invalid email or password" error
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        backgroundColor: Color(0xfff2dfdf),
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // 🔹 Email field
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter Your Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return "Email is required";
                    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    return regex.hasMatch(v)
                        ? null
                        : "Enter a valid email address";
                  },
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                // 🔹 Password field
                TextFormField(
                  controller: _passCtrl,
                  obscureText: passwordVisible,
                  decoration: _inputStyle('Password'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? "Password is required!" : null,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                ),

                const SizedBox(height: 20),

                // 🔹 Login button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 25,
                            height: 25,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Text(
                            'Login',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
