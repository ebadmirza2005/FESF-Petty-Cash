import 'package:flutter/material.dart';
import 'package:project/Screen/add_bill.dart';
import 'package:project/Screen/login.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:io';

class BillScreen extends StatefulWidget {
  final String name, locationCode;
  final File? imageFile;
  final Map<String, dynamic>? billData;

  const BillScreen({
    super.key,
    required this.name,
    required this.locationCode,
    this.imageFile,
    this.billData,
  });

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  double _balance = 0.0, _openingBalance = 0.0;
  String _reportingPeriod = 'Loading...';
  DateTime? balanceUpdatedAt;
  int? _reportingPeriodId; // ✅ Added for backend requirement

  bool _isRefreshing = false;
  bool _isLoadingOpening = false;
  bool _isLoadingReport = false;
  Map<String, dynamic>? _savedBillData;
  File? _savedImageFile;

  @override
  void initState() {
    super.initState();
    _loadSavedBill();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_fetchBalance(), _fetchReportingPeriod()]);
  }

  Future<void> _fetchBalance() async {
    setState(() => _isRefreshing = true);
    final token = await _getToken();
    if (token == null) return setState(() => _isRefreshing = false);

    try {
      final res = await http.get(
        Uri.parse('https://stage-cash.fesf-it.com/api/get-balance'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _balance = (data['current_balance'] ?? 0).toDouble();
          balanceUpdatedAt = _tryParseDate(data['updated_at']);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _fetchReportingPeriod() async {
    final token = await _getToken();
    if (token == null) {
      setState(() {
        _reportingPeriod = 'No auth token';
        _openingBalance = 0.0;
      });
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('https://stage-cash.fesf-it.com/api/get-reporting-period'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['active_reporting_period'];
        final endDate = DateTime.tryParse(data['end_date'] ?? '');
        final periodName = data['name'] ?? 'Unknown';
        final isOutdated = endDate != null && endDate.isBefore(DateTime.now());

        setState(() {
          _reportingPeriodId = data['id']; // ✅ save ID for upload
          _reportingPeriod = isOutdated ? '$periodName (Outdated)' : periodName;
          _openingBalance =
              (data['pivot']?['opening_balance'] as num?)?.toDouble() ?? 0.0;
        });
      } else {
        setState(() => _reportingPeriod = 'Failed (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _reportingPeriod = 'Error: $e');
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  DateTime? _tryParseDate(String? input) {
    if (input == null || input.isEmpty) return null;
    for (final fmt in ['d-M-y h:mm a', 'd-M-y h:m a']) {
      try {
        return DateTime.tryParse(input) ?? DateFormat(fmt).parseLoose(input);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _uploadBill() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';

    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Auth token missing.")));
      return;
    }

    final url = Uri.parse(
      'https://stage-cash.fesf-it.com/api/post-create-bill',
    );
    final request = http.MultipartRequest('POST', url);

    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    final data = widget.billData ?? _savedBillData;
    final imageFile = widget.imageFile ?? _savedImageFile;

    if (data == null || imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No bill data or image found.")),
      );
      return;
    }

    final rawDate = data['date'];
    String formattedDate;

    try {
      final parsedDate = DateFormat('yyyy-MM-dd').parse(rawDate);
      formattedDate = DateFormat('dd-MM-yyyy').format(parsedDate);
    } catch (e) {
      formattedDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    }

    print(formattedDate);

    request.fields['narration'] = data['narration'] ?? '';
    request.fields['expense_head_id'] = data['expenseHead'] ?? '';
    // request.fields['expense_head_id'] = data['expenseHeadId'].toString();
    request.fields['amount'] = data['amount']
        .toString()
        .replaceAll('PKR', '')
        .trim();
    request.fields['date'] = formattedDate;

    if (_reportingPeriodId != null) {
      request.fields['reporting_period_id'] = _reportingPeriodId.toString();
    }

    final file = await http.MultipartFile.fromPath('imageFile', imageFile.path);
    request.files.add(file);

    // 🔍 Debug print (optional)
    print("Uploading fields: ${request.fields}");
    print("Uploading image: ${imageFile.path}");

    try {
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print("Response code: ${response.statusCode}");
      print("Response body: $responseBody");

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Bill uploaded successfully")),
        );
      } else {
        try {
          final errorData = jsonDecode(responseBody);
          String errorMsg = "Upload failed.";

          if (errorData is Map && errorData['errors'] != null) {
            errorMsg = errorData['errors'].entries
                .map((e) => "${e.key}: ${(e.value as List).join(', ')}")
                .join('\n');
          } else if (errorData['message'] != null) {
            errorMsg = errorData['message'];
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("❌ $errorMsg")));
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "❌ Upload failed: ${response.statusCode}\n$responseBody",
              ),
            ),
          );
        }
      }
    } catch (e) {
      print("Upload error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("⚠️ Error: $e")));
    }
  }

  Future<void> saveBillToPrefs(Map<String, dynamic> newBill) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getString('savedBills');
    List<Map<String, dynamic>> bills = [];

    if (existingData != null) {
      final decoded = jsonDecode(existingData);
      bills = List<Map<String, dynamic>>.from(decoded);
    }

    // Convert image file to path (save locally)
    newBill['imagePath'] = (widget.imageFile ?? _savedImageFile)?.path ?? '';

    bills.add(newBill);
    await prefs.setString('savedBills', jsonEncode(bills));
  }

  Future<void> _loadSavedBill() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBillData = prefs.getString('billData');
    final savedImagePath = prefs.getString('billImagePath');

    if (savedBillData != null && savedImagePath != null) {
      final decodedData = jsonDecode(savedBillData) as Map<String, dynamic>;
      final savedImageFile = File(savedImagePath);
      setState(() {
        _savedBillData = decodedData;
        _savedImageFile = savedImageFile;
      });
    }
  }

  Widget _infoCard(String title, Widget trailing) => Card(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(title), trailing],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.locationCode,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w300),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _infoCard(
                'Current Balance',
                Row(
                  children: [
                    _isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Rs. ${NumberFormat('#,###').format(_balance)}'),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _fetchBalance,
                    ),
                  ],
                ),
              ),
              _infoCard(
                'Opening Balance',
                Row(
                  children: [
                    _isLoadingOpening
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Rs. ${NumberFormat('#,###').format(_openingBalance)}',
                          ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        setState(() => _isLoadingOpening = true);
                        await _fetchReportingPeriod();
                        setState(() => _isLoadingOpening = false);
                      },
                    ),
                  ],
                ),
              ),
              _infoCard(
                'Reporting Period',
                Row(
                  children: [
                    _isLoadingReport
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : SizedBox(
                            width: 160,
                            child: Text(
                              _reportingPeriod,
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        setState(() => _isLoadingReport = true);
                        await _fetchReportingPeriod();
                        setState(() => _isLoadingReport = false);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: (widget.billData ?? _savedBillData) != null
                    ? Container(
                        height: 250,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              offset: const Offset(2, 4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((widget.imageFile ?? _savedImageFile) != null)
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(12),
                                  ),
                                  child: Image.file(
                                    widget.imageFile ?? _savedImageFile!,
                                    width: 100,
                                    height: 150,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Narration: ${(widget.billData ?? _savedBillData)?['narration'] ?? ''}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        "Expense Head: ${(widget.billData ?? _savedBillData)?['expenseHead'] ?? ''}",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        "Amount: ${(widget.billData ?? _savedBillData)?['amount'] ?? ''}",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        "Date: ${(widget.billData ?? _savedBillData)?['date'] ?? ''}",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            "No Bill Preview Available",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddBill(
                              name: widget.name,
                              locationCode: widget.locationCode,
                              imageFile: widget.imageFile,
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        "Add Bill",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _uploadBill,
                      child: const Text(
                        "Upload Bill",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
