import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:project/Screen/bill_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';

class AddBill extends StatefulWidget {
  final File? imageFile;
  final String name, locationCode;

  const AddBill({
    super.key,
    required this.name,
    required this.locationCode,
    this.imageFile,
  });

  @override
  State<AddBill> createState() => _AddBillState();
}

class _AddBillState extends State<AddBill> {
  final _formKey = GlobalKey<FormState>();
  final _narrController = TextEditingController();
  final _amountController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  int? _expenseHeadId;
  bool _isLoading = false;
  bool _loadingExpenseHeads = false;
  List<Map<String, dynamic>> _expenseHeads = [];
  File? _image;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadExpenseHeads();
  }

  @override
  void dispose() {
    _narrController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<bool> _hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _loadExpenseHeads() async {
    setState(() => _loadingExpenseHeads = true);
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('expense_heads');

    bool internet = await _hasInternetConnection();

    // Step 1: Pehle cache load kar do taake screen instantly dikhe
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          _expenseHeads = List<Map<String, dynamic>>.from(decoded);
          _expenseHeadId = _expenseHeads.isNotEmpty
              ? _expenseHeads.first['id']
              : null;
        }
      } catch (_) {
        _expenseHeads = [];
      }
    }

    setState(() => _loadingExpenseHeads = false);

    // Step 2: Agar internet hai to background mein fresh data fetch karo
    if (internet) {
      await _fetchExpenseHeads(showSnack: cached == null);
    } else {
      if (_expenseHeads.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Offline — showing last saved expense heads."),
          ),
        );
      }
    }
  }

  Future<void> _fetchExpenseHeads({bool showSnack = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';

    // try {
    final response = await http.get(
      Uri.parse("https://stage-cash.fesf-it.com/api/get-expense-heads"),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final list = decoded is Map && decoded['data'] is List
          ? decoded['data']
          : (decoded is List ? decoded : []);
      _expenseHeads = List<Map<String, dynamic>>.from(list);
      _expenseHeadId = _expenseHeads.isNotEmpty
          ? _expenseHeads.first['id']
          : null;

      // ✅ Cache update
      await prefs.setString('expense_heads', jsonEncode(_expenseHeads));

      if (mounted) {
        setState(() {});
        if (showSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Expense heads updated from server."),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ Server error: ${response.statusCode}")),
        );
      }
    }
  }
  //    catch (e) {
  //     if (mounted) {
  //       _showSnack("⚠️ Error fetching expense heads: $e");
  //     }
  //   }
  // }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.blue),
              title: const Text("Camera"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.purple),
              title: const Text("Gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year),
      lastDate: DateTime.now(),
    );

    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_image == null && widget.imageFile == null) {
      _showSnack("Please select an image.");
      return;
    }

    setState(() => _isLoading = true);

    final selectedExpense = _expenseHeads.firstWhere(
      (h) => h['id'] == _expenseHeadId,
      orElse: () => {'id': 0, 'name': 'Unknown'},
    );

    final newBill = {
      'narration': _narrController.text.trim(),
      'expenseHead': {
        'id': selectedExpense['id'],
        'name': selectedExpense['name'],
      },
      'amount': _amountController.text.trim(),
      'date': DateFormat('dd-MM-yyyy').format(_selectedDate),
    };

    await Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => BillScreen(
          name: widget.name,
          locationCode: widget.locationCode,
          imageFile: _image ?? widget.imageFile,
          billData: newBill,
        ),
      ),
      (route) => false,
    );

    setState(() => _isLoading = false);
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text(
          "Add Bill",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _narrController,
                decoration: const InputDecoration(
                  labelText: "Narration",
                  prefixIcon: Icon(Icons.note_alt_outlined, color: Colors.blue),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v!.isEmpty) {
                    return "Enter narration";
                  } else if (v.length > 250) {
                    return "Narration must be between 1 to 250 character";
                  } else {
                    return null;
                  }
                },
              ),
              const SizedBox(height: 15),
              _loadingExpenseHeads
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                      value: _expenseHeadId,
                      decoration: const InputDecoration(
                        labelText: "Expense Head",
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      items: _expenseHeads
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e['id'],
                              child: Text(
                                e['name'],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _expenseHeadId = v),
                      validator: (v) =>
                          v == null ? "Select expense head" : null,
                    ),

              const SizedBox(height: 15),

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
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: TextFormField(
                          controller: _amountController,
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(),
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
                            if (v == null || v.isEmpty)
                              return 'Please enter amount';
                            final n = num.tryParse(v);
                            if (n == null || n <= 0)
                              return 'Enter valid amount';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 15),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.grey),
                ),
                title: Text(
                  'Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                  style: const TextStyle(fontSize: 16),
                ),
                trailing: const Icon(Icons.calendar_today, color: Colors.blue),
                onTap: _selectDate,
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: _showImagePicker,
                child: Container(
                  height: 170,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: (_image ?? widget.imageFile) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _image ?? widget.imageFile!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : const Center(
                          child: Text(
                            "📷 Tap to select image",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isLoading ? "Uploading..." : "Submit",
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
