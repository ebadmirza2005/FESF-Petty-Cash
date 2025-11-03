import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:project/Screen/uploaded_bills.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project/Screen/big_image.dart';
import 'package:project/Screen/add_bill.dart';
import 'package:project/Screen/login.dart';

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
  int? _reportingPeriodId;

  bool _loadingBalance = false, _loadingReport = false, _loadingOpening = false;

  List<Map<String, dynamic>> _bills = [];
  List<String> _billImagePaths = [];
  int _uploadedBill = 0;

  @override
  void initState() {
    super.initState();
    _loadBills();
    _refreshData();
  }

  Future<void> _refreshData() async =>
      await Future.wait([_fetchBalance(), _fetchReportingPeriod()]);

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> _fetchBalance() async {
    setState(() => _loadingBalance = true);
    final token = await _getToken();
    if (token == null) return;

    try {
      final res = await http.get(
        Uri.parse('https://stage-cash.fesf-it.com/api/get-balance'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _balance = (data['current_balance'] ?? 0).toDouble());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _fetchReportingPeriod() async {
    setState(() {
      _loadingReport = true;
      _loadingOpening = true;
    });
    final token = await _getToken();
    if (token == null) return;

    try {
      final res = await http.get(
        Uri.parse('https://stage-cash.fesf-it.com/api/get-reporting-period'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['active_reporting_period'];
        final periodName = data['name'] ?? 'Unknown';
        final endDate = DateTime.tryParse(data['end_date'] ?? '');
        final outdated = endDate != null && endDate.isBefore(DateTime.now());

        setState(() {
          _reportingPeriodId = data['id'];
          _reportingPeriod = outdated ? '$periodName (Outdated)' : periodName;
          _openingBalance =
              (data['pivot']?['opening_balance'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (e) {
      setState(() => _reportingPeriod = 'No Internet');
    } finally {
      if (mounted) {
        setState(() {
          _loadingReport = false;
          _loadingOpening = false;
        });
      }
    }
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

  Future<void> _saveBills() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bills', jsonEncode(_bills));
    await prefs.setStringList('billImages', _billImagePaths);
    await prefs.setInt('uploadedBillsCount', _uploadedBill);
  }

  Future<void> _loadBills() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBills = prefs.getString('bills');
    final savedPaths = prefs.getStringList('billImages');
    final uploadedCount = prefs.getInt('uploadedBillsCount');

    if (savedBills != null) {
      final decoded = jsonDecode(savedBills);
      if (decoded is List) {
        setState(() {
          _bills = List<Map<String, dynamic>>.from(decoded);
          _billImagePaths = savedPaths ?? [];
          _uploadedBill = uploadedCount ?? _bills.length;
        });
      }
    }

    if (widget.billData != null && widget.imageFile != null) {
      _addNewBill(widget.billData!, widget.imageFile!);
    }
  }

  void _addNewBill(Map<String, dynamic> billData, File imageFile) async {
    setState(() {
      _bills.add(billData);
      _billImagePaths.add(imageFile.path);
    });
    await _saveBills();
  }

  Future<void> _uploadBills() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      _showSnack("Auth token missing.");
      return;
    }
    if (_bills.isEmpty) {
      _showSnack("No bills to upload.");
      return;
    }

    List<Map<String, dynamic>> uploadedBillsList = [];

    for (int i = 0; i < _bills.length; i++) {
      final data = _bills[i];
      final imagePath = _billImagePaths[i];
      final image = File(imagePath);

      final expenseHead = data['expenseHead'];
      final expenseHeadId = expenseHead is Map
          ? expenseHead['id'].toString()
          : data['expenseHeadId']?.toString() ?? '';
      final expenseHeadName = expenseHead is Map
          ? expenseHead['name'].toString()
          : data['expenseHeadName']?.toString() ?? '';

      final url = Uri.parse(
        'https://stage-cash.fesf-it.com/api/post-create-bill',
      );

      final req = http.MultipartRequest('POST', url)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        })
        ..fields.addAll({
          'narration': data['narration'] ?? '',
          'expense_head_id': expenseHeadId,
          'amount':
              double.tryParse(
                data['amount']?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ??
                    '0',
              )?.toString() ??
              '0',
          'date': _formatDate(data['date']),
          if (_reportingPeriodId != null)
            'reporting_period_id': _reportingPeriodId.toString(),
        })
        ..files.add(await http.MultipartFile.fromPath('imageFile', image.path));

      // try {
      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _uploadedBill++;
        });
        _showSnack("✅ Bill uploaded: $expenseHeadName");

        uploadedBillsList.add({
          'expenseHead': {'name': expenseHeadName},
          'date': data['date'],
          'narration': data['narration'],
          'amount': data['amount'],
          'imagePath': image.path,
        });
      } else {
        final err = _parseError(body);
        _showSnack("❌ Failed: $err");
      }
    }
    //   catch (e) {
    //     _showSnack("⚠️ Error uploading: $e");
    //   }
    // }

    if (uploadedBillsList.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('uploadedBillsData');
      List<Map<String, dynamic>> allUploaded = [];

      if (existing != null) {
        allUploaded = List<Map<String, dynamic>>.from(jsonDecode(existing));
      }

      allUploaded.addAll(uploadedBillsList);

      await prefs.setString('uploadedBillsData', jsonEncode(allUploaded));
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bills');
    await prefs.remove('billImages');

    setState(() {
      _bills.clear();
      _billImagePaths.clear();
    });
    await _saveBills();
  }

  String _formatDate(dynamic date) {
    try {
      final parsed = DateFormat('dd-MM-yyyy').parse(date.toString());
      return DateFormat('yyyy-MM-dd').format(parsed);
    } catch (e) {
      return DateFormat('yyyy-MM-dd').format(DateTime.now());
    }
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data['errors'] != null) {
        return (data['errors'] as Map).entries
            .map((e) => "${e.key}: ${(e.value as List).join(', ')}")
            .join('\n');
      }
      return data['message'] ?? "Upload failed.";
    } catch (_) {
      return "Upload failed.";
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              widget.locationCode,
              style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 20),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 13),
            child: DropdownButton<String>(
              menuWidth: 90,
              dropdownColor: Colors.blue,
              icon: const Icon(Icons.logout, color: Colors.white),
              underline: const SizedBox(),
              onChanged: (value) {
                if (value == 'logout') _logout();
              },
              items: const [
                DropdownMenuItem(
                  value: 'logout',
                  child: Center(
                    child: Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RefreshIndicator(
          color: Colors.blue,
          onRefresh: _refreshData,
          child: ListView(
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Current Balance:"),
                          _loadingBalance
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blue,
                                )
                              : Text(
                                  'Rs. ${NumberFormat('#,###').format(_balance)}',
                                ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Opening Balance:"),
                          _loadingOpening
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blue,
                                )
                              : Text(
                                  'Rs. ${NumberFormat('#,###').format(_openingBalance)}',
                                ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Reporting Period:"),
                          _loadingReport
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blue,
                                )
                              : Text(_reportingPeriod),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      "Uploaded Bills",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "$_uploadedBill bills",
                      style: const TextStyle(
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                onPressed: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => UploadedBills()),
                  );
                  final prefs = await SharedPreferences.getInstance();
                  setState(() {
                    _uploadedBill = prefs.getInt('uploadedBillsCount') ?? 0;
                  });
                },
              ),
              const SizedBox(height: 30),

              if (_bills.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Text(
                      "No bills added yet",
                      style: TextStyle(wordSpacing: 5, letterSpacing: 2),
                    ),
                  ),
                )
              else
                Column(
                  children: List.generate(_bills.length, (i) {
                    final bill = _bills[i];
                    final img = File(_billImagePaths[i]);
                    final expenseHead = bill['expenseHead'];
                    final expenseHeadName = expenseHead is Map
                        ? expenseHead['name'].toString()
                        : bill['expenseHeadName']?.toString() ?? 'N/A';

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BigImage(imageFile: img),
                            ),
                          ),
                          child: Image.file(
                            img,
                            width: 55,
                            height: 55,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          expenseHeadName,
                          style: const TextStyle(fontSize: 15),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Text("Date: ${bill['date']}"),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "Narration: ${bill['narration']}",
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _bills.removeAt(i);
                                      _billImagePaths.removeAt(i);
                                    });
                                    _saveBills();
                                  },
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            Text("Amount: ${bill['amount']}"),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 120),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddBill(
                            name: widget.name,
                            locationCode: widget.locationCode,
                          ),
                        ),
                      ),
                      child: const Text(
                        "Add Bill",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _uploadBills,
                      child: const Text(
                        "Upload Bills",
                        style: TextStyle(fontWeight: FontWeight.bold),
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
