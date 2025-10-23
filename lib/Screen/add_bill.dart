import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class AddBill extends StatefulWidget {
  const AddBill({super.key});

  @override
  State<AddBill> createState() => _AddBillState();
}

class _AddBillState extends State<AddBill> {
  final _formKey = GlobalKey<FormState>();
  final _narrController = TextEditingController();
  int? _expenseHeadId;
  List<Map<String, dynamic>> _expenseHeads = [];
  bool _loadingExpenseHeads = false;

  File? image;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadExpenseHeads();
  }

  @override
  void dispose() {
    _narrController.dispose();
    super.dispose;
  }

  Future<bool> _hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  bool _shouldFetchExpenseHeads() {
    final now = DateTime.now();
    return now.day == 1 || now.day == 16;
  }

  Future<void> loadExpenseHeads() async {
    setState(() => _loadingExpenseHeads = true);
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('expense_heads');

    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          _expenseHeads = List<Map<String, dynamic>>.from(decoded);
          _expenseHeadId = _expenseHeads.isNotEmpty
              ? _expenseHeads[0]['id'] as int?
              : null;
        }
      } catch (_) {
        _expenseHeads = [];
        _expenseHeadId = null;
      }
      setState(() => _loadingExpenseHeads = false);
    } else if (await _hasInternetConnection()) {
      await fetchExpenseHeads();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No internet. Expense Heads not available"),
          ),
        );
      }
      setState(() {
        _expenseHeads = [];
        _expenseHeadId = null;
        _loadingExpenseHeads = false;
      });
    }

    if (await _hasInternetConnection() && _shouldFetchExpenseHeads()) {
      await fetchExpenseHeads();
    }
  }

  Future<void> fetchExpenseHeads() async {
    setState(() => _loadingExpenseHeads = true);
    final url = Uri.parse(
      "https://stage-cash.fesf-it.com/api/get-expense-heads",
    );
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';

    if (token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Auth token missing.')));
      }
      setState(() {
        _expenseHeads = [];
        _expenseHeadId = null;
        _loadingExpenseHeads = false;
      });
      return;
    }

    try {
      final resp = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        List<dynamic> listData = [];

        if (decoded is Map && decoded.containsKey('data')) {
          listData = decoded['data'];
        } else if (decoded is List) {
          listData = decoded;
        } else {
          throw Exception('Unexpected response format');
        }

        _expenseHeads = listData
            .where(
              (item) =>
                  item is Map &&
                  item.containsKey('id') &&
                  item.containsKey('name') &&
                  item['id'] != null &&
                  item['name'] != null,
            )
            .map<Map<String, dynamic>>(
              (item) => {
                'id': item['id'],
                'name': item['name'],
                'code': item['code'],
              },
            )
            .toList();

        _expenseHeadId = _expenseHeads.isNotEmpty
            ? _expenseHeads[0]['id'] as int?
            : null;

        await prefs.setString('expense_heads', jsonEncode(_expenseHeads));
      } else {
        throw Exception('Server: ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Expense head load error: $e')));
      }
    } finally {
      setState(() => _loadingExpenseHeads = false);
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera, color: Colors.blue),
              title: Text(
                "Camera",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                _pickImage(ImageSource.camera);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Colors.pink),
              title: Text(
                "Gallery",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                _pickImage(ImageSource.gallery);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        image = File(pickedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text(
          "Bill Info",
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Narration
              TextFormField(
                controller: _narrController,
                decoration: InputDecoration(
                  labelText: "Narration",
                  prefixIcon: const Icon(Icons.note, color: Colors.blue),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? "Please Enter Narration" : null,
              ),
              const SizedBox(height: 23),

              // Expense Head Dropdown
              _loadingExpenseHeads
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : DropdownButtonFormField<int>(
                      key: ValueKey(_expenseHeads.length),
                      decoration: InputDecoration(
                        labelText: 'Expense Head',
                        prefixIcon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.deepPurple,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon:
                          const SizedBox.shrink(), // 🔹 hides the default dropdown arrow
                      value:
                          (_expenseHeads.isNotEmpty &&
                              _expenseHeads.any(
                                (h) => h['id'] == _expenseHeadId,
                              ))
                          ? _expenseHeadId
                          : null,
                      items: _expenseHeads.map((h) {
                        return DropdownMenuItem<int>(
                          value: h['id'] as int,
                          child: Text(
                            h['name']?.toString() ?? '-',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _expenseHeadId = v),
                      validator: (v) {
                        if (v == null ||
                            !_expenseHeads.any((h) => h['id'] == v)) {
                          return 'Please select expense head';
                        }
                        return null;
                      },
                      style: const TextStyle(fontSize: 13),
                    ),

              const SizedBox(height: 25),

              // Amount Field
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Colors.deepPurple.withOpacity(0.4),
                    width: 0.7,
                  ),
                ),
                color: Colors.deepPurple.withOpacity(0.04),
                elevation: 0,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.11),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text(
                          'PKR',
                          style: TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: TextFormField(
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 11,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please enter amount';
                            }
                            final n = num.tryParse(v);
                            if (n == null || n <= 0) {
                              return 'Enter valid amount';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 50),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: _showPicker,
                  child: Text(
                    "Upload Image",
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
            ],
          ),
        ),
      ),
    );
  }
}
