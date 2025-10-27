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
  int _billCount = 0;

  List<Map<String, dynamic>> _expenseHeads = [];
  List<Map<String, dynamic>> _submitBills = [];

  File? image;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    loadExpenseHeads();
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
              ? _expenseHeads.first['id']
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
        _loadingExpenseHeads = true;
      });
      return;
    }

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);

        // ✅ Directly use the list as-is from API (no filtering/sorting)
        final List<dynamic> listData =
            decoded is Map && decoded.containsKey('data')
            ? decoded['data']
            : (decoded is List ? decoded : []);

        _expenseHeads = List<Map<String, dynamic>>.from(listData);

        // ✅ Set first ID as default (optional)
        _expenseHeadId = _expenseHeads.isNotEmpty
            ? _expenseHeads.first['id']
            : null;

        // ✅ Save exactly as API returned (for caching)
        await prefs.setString('expense_heads', jsonEncode(_expenseHeads));
      } else {
        throw Exception(
          'Failed to load expense heads (code: ${response.statusCode})',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading expense heads: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingExpenseHeads = false);
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, color: Colors.blue),
            title: const Text(
              "Camera",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: () {
              _pickImage(ImageSource.camera);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.pink),
            title: const Text(
              "Gallery",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: () {
              _pickImage(ImageSource.gallery);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final firstAllowedDate = DateTime(prevYear, prevMonth, 1);
    final lastAllowedDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: firstAllowedDate,
      lastDate: lastAllowedDate,
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.deepPurple),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() => image = File(pickedFile.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (image == null && widget.imageFile == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select an image")));
      return;
    }

    setState(() => _isLoading = true);

    final selectedExpense = _expenseHeads.firstWhere(
      (h) => h['id'] == _expenseHeadId,
      orElse: () => {'name': 'Unknown'},
    );

    final newBill = {
      'narration': _narrController.text,
      'expenseHead': selectedExpense['name'],
      'amount': '${_amountController.text}/=',
      'date': DateFormat('dd/MM/yyyy').format(_selectedDate),
      'image': image ?? widget.imageFile,
    };

    _submitBills.add(newBill);
    _billCount++;

    if (!mounted) return;

    await Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => BillScreen(
          name: widget.name,
          locationCode: widget.locationCode,
          imageFile: image ?? widget.imageFile,
          billData: newBill,
        ),
      ),
      (route) => false,
    );

    setState(() {
      image = null;
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Bill $_billCount added successfully!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text(
          "Bill Info",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                    (v == null || v.isEmpty) ? "Please enter narration" : null,
              ),
              const SizedBox(height: 20),

              _loadingExpenseHeads
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: 'Expense Head',
                        prefixIcon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.blue,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      value: _expenseHeadId,
                      items: _expenseHeads.map((h) {
                        return DropdownMenuItem<int>(
                          value: h['id'],
                          child: Text(
                            h['name'].toString(),
                          ), // API jaisa hi name
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _expenseHeadId = v;
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Please select expense head' : null,
                    ),

              const SizedBox(height: 20),

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

              const SizedBox(height: 20),

              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                  side: const BorderSide(color: Colors.deepPurple, width: 0.6),
                ),
                title: Text(
                  'Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                ),
                trailing: const Icon(Icons.calendar_today, color: Colors.blue),
                onTap: () => _selectDate(context),
              ),

              const SizedBox(height: 25),

              GestureDetector(
                onTap: _showPicker,
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: (image ?? widget.imageFile) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            image ?? widget.imageFile!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : const Center(
                          child: Text(
                            "Tap to select image",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Submit",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
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
