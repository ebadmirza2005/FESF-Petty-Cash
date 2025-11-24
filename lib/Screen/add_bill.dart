import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:project/Screen/bill_screen.dart';
import 'package:project/Screen/crop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

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
  DateTime? _selectedDate;
  String? activeDate;

  @override
  void initState() {
    super.initState();
    _loadExpenseHeads();
    _loadCachedReportingPeriod(); // load last saved reporting period
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

    if (internet) {
      await _fetchExpenseHeads(showSnack: cached == null);
    } else {
      if (_expenseHeads.isNotEmpty) {
        _showSnack("⚠️ Offline — showing last saved expense heads.");
      } else {
        _showSnack("⚠️ No internet and no saved data found.");
      }
    }
  }

  Future<void> _fetchExpenseHeads({bool showSnack = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
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

      await prefs.setString('expense_heads', jsonEncode(_expenseHeads));

      if (mounted) {
        setState(() {});
        if (showSnack) _showSnack("✅ Expense heads updated from server.");
      }
    } else {
      _showSnack("⚠️ Server error: ${response.statusCode}");
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // Load cached reporting period on screen init
  Future<void> _loadCachedReportingPeriod() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('reporting_period');
    if (cached != null) {
      try {
        final data = jsonDecode(cached);
        final dateFormat = DateFormat('dd-MMM-yy');
        DateTime endDate = dateFormat.parse(data['end_date']);
        setState(() {
          _selectedDate = endDate.isAfter(DateTime.now())
              ? DateTime.now()
              : endDate;
          activeDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
        });
      } catch (_) {}
    }
  }

  Future<void> _selectDate() async {
    final prefs = await SharedPreferences.getInstance();
    bool internet = await _hasInternetConnection();

    DateTime today = DateTime.now();
    DateTime startDate = today.subtract(const Duration(days: 30));
    DateTime allowedEndDate = today;

    final cached = prefs.getString('reporting_period');
    if (cached != null) {
      try {
        final data = jsonDecode(cached);
        final dateFormat = DateFormat('dd-MMM-yy');
        startDate = dateFormat.parse(data['start_date']);
        DateTime apiEnd = dateFormat.parse(data['end_date']);
        allowedEndDate = apiEnd.isAfter(today) ? today : apiEnd;
      } catch (_) {}
    }

    if (internet) {
      final token = await _getToken();
      if (token != null) {
        try {
          final res = await http.get(
            Uri.parse(
              'https://stage-cash.fesf-it.com/api/get-reporting-period',
            ),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (res.statusCode == 200) {
            final body = jsonDecode(res.body);
            final data = body['active_reporting_period'];
            await prefs.setString('reporting_period', jsonEncode(data));

            final dateFormat = DateFormat('dd-MMM-yy');
            startDate = dateFormat.parse(data['start_date']);
            DateTime apiEnd = dateFormat.parse(data['end_date']);
            allowedEndDate = apiEnd.isAfter(today) ? today : apiEnd;
          }
        } catch (_) {}
      }
    } else {
      _showSnack("⚠️ Offline — using saved reporting period");
    }

    DateTime initialDate = _selectedDate ?? allowedEndDate;
    if (initialDate.isBefore(startDate)) initialDate = startDate;
    if (initialDate.isAfter(allowedEndDate)) initialDate = allowedEndDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: startDate,
      lastDate: allowedEndDate,
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        activeDate = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<File> compressImage(File file) async {
    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return file;

    img.Image resized = img.copyResize(image, width: 1200);
    final compressedBytes = img.encodeJpg(resized, quality: 70);

    final tempPath = "${file.path}.jpg";
    final compressedFile = File(tempPath);
    await compressedFile.writeAsBytes(compressedBytes);
    return compressedFile;
  }

  Future<void> pickImage(bool fromGallery) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: fromGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 50,
      );
      if (pickedFile == null) return;

      File file = await compressImage(File(pickedFile.path));
      final String? validationMessage = await _validateImage(file);
      if (validationMessage != null) {
        if (mounted) _showSnack(validationMessage);
        return;
      }

      final croppedFilePath = await Navigator.push<String?>(
        context,
        MaterialPageRoute(builder: (_) => CroppedImage(image: file)),
      );

      if (!mounted) return;
      if (croppedFilePath != null && croppedFilePath.isNotEmpty) {
        setState(() => _image = File(croppedFilePath));
      }
    } catch (_) {
      if (mounted) _showSnack("Error picking image");
    }
  }

  Future<String?> _validateImage(File file) async {
    String extension = file.path.split('.').last.toLowerCase();
    List<String> allowed = ['jpg', 'jpeg', 'png'];
    if (!allowed.contains(extension)) return "❌ Only JPG or PNG allowed";

    int fileSize = await file.length();
    if (fileSize > 15 * 1024 * 1024) return "⚠️ Max 15MB allowed";
    if (fileSize == 0) return "❌ File is empty";

    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return "❌ Not a valid image";
      if (image.width < 200 || image.height < 200) {
        return "⚠️ Min 200x200 required";
      }
    } catch (_) {
      return "❌ Unable to read image";
    }

    return null;
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
      'date': DateFormat('dd-MM-yyyy').format(_selectedDate!),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _loadingExpenseHeads
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                      initialValue: _expenseHeadId,
                      decoration: const InputDecoration(
                        labelText: "Expense Head",
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                        focusedBorder: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(width: 2, color: Colors.blue),
                        ),
                      ),
                      isExpanded: true,
                      items: _expenseHeads.map((e) {
                        return DropdownMenuItem<int>(
                          value: e['id'],
                          child: Text(
                            e['name'],
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _expenseHeadId = v),
                      validator: (v) =>
                          v == null ? "Select expense head" : null,
                    ),
              const SizedBox(height: 15),

              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (_) => SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.photo_camera,
                              color: Colors.blue,
                            ),
                            title: const Text("Camera"),
                            onTap: () {
                              Navigator.pop(context);
                              pickImage(false);
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.photo_library,
                              color: Colors.purple,
                            ),
                            title: const Text("Gallery"),
                            onTap: () {
                              Navigator.pop(context);
                              pickImage(true);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 170,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(
                            _image!,
                            fit: BoxFit.contain,
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

              const SizedBox(height: 15),

              FormField<DateTime>(
                validator: (value) =>
                    _selectedDate == null ? "Please select a date" : null,
                builder: (state) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _selectDate,
                        child: Container(
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: state.hasError ? Colors.red : Colors.grey,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                _selectedDate == null
                                    ? "Select Date"
                                    : "Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}",
                                style: TextStyle(
                                  color: _selectedDate == null
                                      ? (state.hasError
                                            ? Colors.red
                                            : Colors.grey)
                                      : Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (state.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, left: 5),
                          child: Text(
                            state.errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter amount';
                  final n = num.tryParse(v);
                  if (n == null || n <= 0) return 'Enter valid amount';
                  if (n > 50000) return 'Enter number between 1-50000';
                  return null;
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _narrController,
                decoration: const InputDecoration(
                  labelText: "Narration",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "Enter narration";
                  if (v.length > 250) return "Narration max 250 characters";
                  return null;
                },
              ),

              const SizedBox(height: 15),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Submit",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
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
