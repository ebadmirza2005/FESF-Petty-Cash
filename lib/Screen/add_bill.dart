import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:project/Screen/bill_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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
  int? _expenseHeadId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _expenseHeads = [];
  List<Map<String, dynamic>> _submitBills = [];
  bool _loadingExpenseHeads = false;
  DateTime _selectedDate = DateTime.now();

  File? image;
  final ImagePicker _picker = ImagePicker();
  int _billCount = 0;

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
              leading: const Icon(Icons.photo_camera, color: Colors.blue),
              title: const Text(
                "Camera",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                _pickImage(ImageSource.camera);
                Navigator.of(context).pop();
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
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();

    // Ye ab pichlay maheenay ke first day ko allow karega
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;

    // Pichlay maheenay ka pehla din
    final firstAllowedDate = DateTime(prevYear, prevMonth, 1);

    // Aaj tak ki date allowed
    final lastAllowedDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(lastAllowedDate)
          ? lastAllowedDate
          : _selectedDate.isBefore(firstAllowedDate)
          ? firstAllowedDate
          : _selectedDate,
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
      setState(() {
        image = File(pickedFile.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    if (image == null && widget.imageFile == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select an image")));
      setState(() => _isLoading = false);
      return;
    }

    final selectExpense = _expenseHeads.firstWhere(
      (h) => h['id'] == _expenseHeadId,
      orElse: () => {'name': 'Unknown'},
    );

    final newBill = {
      'narration': _narrController.text,
      'expenseHead': selectExpense['name'],
      'amount': 'PKR ${_amountController.text}',
      'date': DateFormat('d/M/Y').format(_selectedDate),
      'image': image ?? widget.imageFile,
    };

    _submitBills.add(newBill);
    _billCount++;

    // Navigate to BillScreen
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
      (Route<dynamic> route) => false,
    );

    // 👇 yahan image clear kar rahe hain
    setState(() {
      image = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Bill $_billCount added successfully!")),
    );

    setState(() => _isLoading = false);

    if (_billCount >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You have added 10 bills successfully ✅")),
      );
      Navigator.pop(context);
      return;
    }

    final addAnother = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Bill Added"),
        content: Text(
          "You have added $_billCount bills.\nDo you want to add another one?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (addAnother == true) {
      _formKey.currentState!.reset();
      _narrController.clear();
      _amountController.clear();
      setState(() {
        image = null;
        _expenseHeadId = null;
        _selectedDate = DateTime.now();
      });
    } else {
      Navigator.pop(context);
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
                          color: Colors.blue,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const SizedBox.shrink(), // right icon hataya gaya
                      hint: const Text(
                        'Select Expense Head',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),

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
                            h['name']?.toString() ??
                                '-', // API key yahan match karna
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

              // Date Picker
              ListTile(
                shape: BeveledRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                  side: const BorderSide(color: Colors.deepPurple, width: 0.6),
                ),
                title: Text(
                  'Date: ${DateFormat('dd/MM/yy').format(_selectedDate)}',
                ),
                trailing: const Icon(Icons.calendar_today, color: Colors.blue),
                onTap: () => _selectDate(context),
              ),

              const SizedBox(height: 30),

              // Image Picker
              Container(
                width: 90,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      offset: const Offset(4, 4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: (image ?? widget.imageFile) != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          image ?? widget.imageFile!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 200,
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Drag & Drop your files or",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: _showPicker,
                              child: const Text(
                                "Browse",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 30),

              // Submit Button
              SizedBox(
                width: MediaQuery.of(context).size.width,
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
                  child: const Text(
                    "Submit",
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
