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
  String? tempImagePath;
  DateTime _selectedDate = DateTime.now();
  FocusNode FocusColor = FocusNode();

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

  Future<void> pickImage(bool fromGallery) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    File file = File(pickedFile.path);
    String? validationMessage = await _validateImage(file);

    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    tempImagePath = pickedFile.path; // store original temporarily

    final croppedFilePath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CroppedImage(imagePath: pickedFile.path),
      ),
    );

    if (!mounted) return;

    setState(() {
      if (croppedFilePath != null && croppedFilePath is String) {
        _image = File(croppedFilePath); // Only show cropped image
      }
    });

    print("🖼️ Selected image: ${_image?.path}");
  }

  Future<String?> _validateImage(File file) async {
    String extension = file.path.split('.').last.toLowerCase();
    List<String> allowed = ['jpg', 'jpeg', 'png'];
    if (!allowed.contains(extension))
      return "❌ Only JPG or PNG images are allowed.";

    int fileSize = await file.length();
    const int maxSize = 5 * 1024 * 1024;
    if (fileSize > maxSize) return "⚠️ Image size must be under 5 MB.";
    if (fileSize == 0) return "❌ Image file is empty.";

    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return "❌ File is not a valid image.";
      if (image.width < 200 || image.height < 200) {
        return "⚠️ Image resolution too low (min 200x200 required).";
      }
    } catch (e) {
      return "❌ Unable to read image.";
    }

    return null;
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    DateTime startDate = DateTime(2025, 10, 16);
    DateTime endDate = DateTime(2025, 10, 31);
    final allowedEndDate = endDate.isAfter(now) ? now : endDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(startDate)
          ? startDate
          : (_selectedDate.isAfter(allowedEndDate)
                ? allowedEndDate
                : _selectedDate),
      firstDate: startDate,
      lastDate: allowedEndDate,
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
              _loadingExpenseHeads
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                      value: _expenseHeadId,
                      decoration: const InputDecoration(
                        labelText: "Expense Head",
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(width: 2, color: Colors.blue),
                        ),
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
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Image.file(
                              _image!,
                              key: ValueKey(_image!.path),
                              fit: BoxFit.cover,
                            ),
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
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                width: 2,
                                color: Colors.blue,
                              ),
                            ),
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
                            if (v == null || v.isEmpty)
                              return 'Please enter amount';
                            final n = num.tryParse(v);
                            if (n == null || n <= 0)
                              return 'Enter valid amount';
                            if (n > 50000)
                              return "Enter number between 1 to 50000";
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _narrController,
                focusNode: FocusColor,
                cursorColor: Colors.blue,
                decoration: const InputDecoration(
                  labelText: "Narration",
                  labelStyle: TextStyle(fontWeight: FontWeight.w300),
                  hintText: "Enter Narration",
                  hintStyle: TextStyle(fontWeight: FontWeight.w300),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(width: 2, color: Colors.blue),
                  ),
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note_alt_outlined, color: Colors.blue),
                ),
                validator: (v) {
                  if (v!.isEmpty) return "Enter narration";
                  if (v.length > 250)
                    return "Narration must be between 1 to 250 characters";
                  return null;
                },
              ),

              const SizedBox(height: 15),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
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
                      : const Text(
                          "Submit",
                          style: TextStyle(
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
