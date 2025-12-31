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
  String _lastUpdated = '';
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedFinancialData().then((_) {
      _loadBills();
      _refreshData();
    });
  }

  Future<void> _refreshData() async =>
      await Future.wait([_fetchBalance(), _fetchReportingPeriod()]);

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> _loadSavedFinancialData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedBalance = prefs.getDouble('saved_balance');
    final savedPeriod = prefs.getString('saved_reporting_period');
    final savedOpening = prefs.getDouble('saved_opening_balance');
    final savedUpdated = prefs.getString('saved_last_updated');
    setState(() {
      _lastUpdated = savedUpdated ?? '';
    });

    setState(() {
      _balance = savedBalance ?? 0.0;
      _reportingPeriod = savedPeriod ?? 'Loading...';
      _openingBalance = savedOpening ?? 0.0;
    });
  }

  Future<void> _fetchBalance() async {
    setState(() => _loadingBalance = true);
    final token = await _getToken();
    final prefs = await SharedPreferences.getInstance();

    try {
      if (token == null) throw Exception("No token");
      final res = await http.get(
        Uri.parse('https://stage-cash.fesf-it.com/api/get-balance'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final balance = (data['current_balance'] ?? 0).toDouble();
        setState(() => _balance = balance);

        await prefs.setDouble('saved_balance', balance);
      } else {
        throw Exception("Server Error");
      }
    } catch (e) {
      final saved = prefs.getDouble('saved_balance');
      if (saved != null) {
        setState(() => _balance = saved);
      } else {
        setState(() => _balance = 0.0);
      }
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
    final prefs = await SharedPreferences.getInstance();

    try {
      if (token == null) throw Exception("No token");
      final res = await http.get(
        Uri.parse('https://stage-cash.fesf-it.com/api/get-reporting-period'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['active_reporting_period'];
        final periodName = data['name'] ?? 'Unknown';
        final startDate = data['start_date'] ?? '';
        final endDate = data['end_date'] ?? '';

        final parsedEndDate = DateTime.tryParse(endDate);
        final outdated =
            parsedEndDate != null && parsedEndDate.isBefore(DateTime.now());
        final reportingText = outdated ? '$periodName (Outdated)' : periodName;
        final openingBalance =
            (data['pivot']?['opening_balance'] as num?)?.toDouble() ?? 0.0;

        setState(() {
          _reportingPeriodId = data['id'];
          _reportingPeriod = reportingText;
          _openingBalance = openingBalance;
        });

        await prefs.setString('saved_reporting_period', reportingText);
        await prefs.setDouble('saved_opening_balance', openingBalance);

        await prefs.setString('report_start_date', startDate);
        await prefs.setString('report_end_date', endDate);

        if (startDate.isNotEmpty && endDate.isNotEmpty) {
          await prefs.setString('reporting_period', '$startDate - $endDate');
        }
      } else {
        throw Exception("Server Error");
      }
      final now = DateFormat('dd-MM-yyyy').format(DateTime.now());

      await prefs.setString('saved_last_updated', now);

      setState(() {
        _lastUpdated = now;
      });
    } catch (e) {
      final savedPeriod = prefs.getString('saved_reporting_period');
      final savedOpening = prefs.getDouble('saved_opening_balance');
      final savedUpdated = prefs.getString('saved_last_updated');
      if (savedUpdated != null) {
        setState(() => _lastUpdated = savedUpdated);
      } else {
        setState(() => _lastUpdated = 'No previous update');
      }

      if (savedPeriod != null && savedOpening != null) {
        setState(() {
          _reportingPeriod = savedPeriod;
          _openingBalance = savedOpening;
        });
      } else {
        setState(() {
          _reportingPeriod = 'No Internet';
          _openingBalance = 0.0;
        });
      }
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Center(
            child: Text(
              "Confirmation",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ),
          content: Text(
            "If you log out, all your data will be lost. Do you want to log out?",
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.exit_to_app,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
              label: Text(
                "Cancel",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              icon: Icon(
                Icons.logout,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
              label: Text(
                "Logout",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveBills({bool updateUploadedCount = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bills', jsonEncode(_bills));
    await prefs.setStringList('billImages', _billImagePaths);

    if (updateUploadedCount) {
      await prefs.setInt('uploadedBillsCount', _uploadedBill);
    }
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
          _uploadedBill = uploadedCount ?? 0;
        });
      }
    }

    // Add new bill if coming from AddBill screen
    if (widget.billData != null && widget.imageFile != null) {
      _addNewBill(widget.billData!, widget.imageFile!);
    }
  }

  void _addNewBill(Map<String, dynamic> billData, File imageFile) async {
    setState(() {
      _bills.add(billData);
      _billImagePaths.add(imageFile.path);
    });
    await _saveBills(
      updateUploadedCount: false,
    ); // Do NOT overwrite uploaded count
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

    final confirmUpload = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Center(
            child: Text(
              "Confirmation",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ),
          content: const Text(
            "All your data will be uploaded to the server and cannot be edited afterward.",
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.cancel, color: Colors.green),
              label: const Text(
                "Cancel",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.upload, color: Colors.red),
              label: const Text(
                "Upload",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmUpload != true) {
      _showSnack("Upload cancelled.");
      return;
    }

    setState(() => uploading = true);

    final prefs = await SharedPreferences.getInstance();
    int uploadedCount = prefs.getInt('uploadedBillsCount') ?? _uploadedBill;
    List<Map<String, dynamic>> uploadedBillsList = [];

    for (int i = 0; i < _bills.length; i++) {
      try {
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
                  data['amount']?.toString().replaceAll(
                        RegExp(r'[^0-9.]'),
                        '',
                      ) ??
                      '0',
                )?.toString() ??
                '0',
            'date': _formatDate(data['date']),
            if (_reportingPeriodId != null)
              'reporting_period_id': _reportingPeriodId.toString(),
          })
          ..files.add(
            await http.MultipartFile.fromPath('imageFile', image.path),
          );

        final res = await req.send();
        final body = await res.stream.bytesToString();

        if (res.statusCode == 200 || res.statusCode == 201) {
          uploadedCount++;
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
      } catch (e) {
        _showSnack("⚠️ Error uploading: $e");
      }
    }

    if (uploadedBillsList.isNotEmpty) {
      final existing = prefs.getString('uploadedBillsData');
      List<Map<String, dynamic>> allUploaded = [];
      if (existing != null) {
        allUploaded = List<Map<String, dynamic>>.from(jsonDecode(existing));
      }
      allUploaded.addAll(uploadedBillsList);
      await prefs.setString('uploadedBillsData', jsonEncode(allUploaded));
    }

    setState(() {
      _bills.clear();
      _billImagePaths.clear();
      _uploadedBill = uploadedCount;
      uploading = false;
    });

    await _saveBills(updateUploadedCount: true);

    _showSnack("✅ All bills uploaded successfully!");
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
    double width = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(width: 85),
            Text(
              widget.locationCode,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 13),
            child: IconButton(
              onPressed: _logout,
              icon: Icon(Icons.logout, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: Container(
        width: width * width,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: RefreshIndicator(
            color: Colors.blue,
            onRefresh: _refreshData,
            child: ListView(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Text(
                                  "Current Balance",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(height: 10),
                                _loadingBalance
                                    ? const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.blue,
                                      )
                                    : Text(
                                        'Rs. ${NumberFormat('#,###').format(_balance)}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.black,
                                        ),
                                      ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Text(
                                  "Opening Balance",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(height: 10),
                                _loadingOpening
                                    ? const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.blue,
                                      )
                                    : Text(
                                        'Rs. ${NumberFormat('#,###').format(_openingBalance)}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.black,
                                        ),
                                      ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              "Reporting Period: ",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(width: 40),
                            _loadingReport
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.blue,
                                  )
                                : Text(
                                    _reportingPeriod,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.black,
                                    ),
                                  ),
                          ],
                        ),
                        SizedBox(height: 20),
                        Center(
                          child: Text(
                            "Last Online At   :   ${_lastUpdated.isNotEmpty ? _lastUpdated : '---'}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.only(left: 20, top: 5, bottom: 5),
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        "Uploaded Bills",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "$_uploadedBill bills",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UploadedBills(),
                            ),
                          );
                          final prefs = await SharedPreferences.getInstance();
                          setState(() {
                            _uploadedBill =
                                prefs.getInt('uploadedBillsCount') ?? 0;
                          });
                        },
                        icon: Icon(
                          Icons.arrow_forward,
                          fontWeight: FontWeight.bold,
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

                if (_bills.isEmpty)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 150, bottom: 90),
                      child: Text(
                        "No bills added yet",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          wordSpacing: 5,
                          letterSpacing: 4,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  )
                else
                  uploading
                      ? Column(
                          children: [
                            SizedBox(height: 70),
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                color: Colors.blue,
                                strokeWidth: 5,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Container(
                                height: 265,
                                child: ListView(
                                  children: [
                                    Column(
                                      children: List.generate(_bills.length, (
                                        i,
                                      ) {
                                        final bill = _bills[i];
                                        final img = File(_billImagePaths[i]);
                                        final expenseHead = bill['expenseHead'];
                                        final expenseHeadName =
                                            expenseHead is Map
                                            ? expenseHead['name'].toString()
                                            : bill['expenseHeadName']
                                                      ?.toString() ??
                                                  'N/A';

                                        return Card(
                                          color: Colors.grey[300],
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                          elevation: 5,
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 12,
                                          ),
                                          shadowColor: Colors.black26,
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 30,
                                                      ),
                                                  child: GestureDetector(
                                                    onTap: () => Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            BigImage(
                                                              imageFile: img,
                                                            ),
                                                      ),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      child: Image.file(
                                                        img,
                                                        width: 65,
                                                        height: 65,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        expenseHeadName,
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Date: ${bill['date']}",
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Narration: ${bill['narration']}",
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Text(
                                                            "Amount: Rs ${bill['amount']}",
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .green,
                                                                ),
                                                          ),
                                                          IconButton(
                                                            onPressed: () {
                                                              showDialog(
                                                                context:
                                                                    context,
                                                                builder:
                                                                    (
                                                                      BuildContext
                                                                      context,
                                                                    ) {
                                                                      return AlertDialog(
                                                                        title: Center(
                                                                          child: Text(
                                                                            "Alert!",
                                                                            style: TextStyle(
                                                                              fontWeight: FontWeight.bold,
                                                                              color: Colors.red,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        content:
                                                                            Text(
                                                                              "If you want to remove it so your bill and data will be lost. Do you wanna remove.",
                                                                            ),
                                                                        actions: [
                                                                          ElevatedButton.icon(
                                                                            style: ElevatedButton.styleFrom(
                                                                              shape: RoundedRectangleBorder(
                                                                                borderRadius: BorderRadius.circular(
                                                                                  5,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            onPressed: () {
                                                                              Navigator.pop(
                                                                                context,
                                                                              );
                                                                            },
                                                                            icon: Icon(
                                                                              Icons.exit_to_app,
                                                                              color: Colors.green,
                                                                              fontWeight: FontWeight.bold,
                                                                            ),
                                                                            label: Text(
                                                                              "Cancel",
                                                                              style: TextStyle(
                                                                                fontWeight: FontWeight.bold,
                                                                                color: Colors.green,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                10,
                                                                          ),
                                                                          ElevatedButton.icon(
                                                                            style: ElevatedButton.styleFrom(
                                                                              shape: RoundedRectangleBorder(
                                                                                borderRadius: BorderRadius.circular(
                                                                                  5,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            onPressed: () {
                                                                              setState(
                                                                                () {
                                                                                  _bills.removeAt(
                                                                                    i,
                                                                                  );
                                                                                  _billImagePaths.removeAt(
                                                                                    i,
                                                                                  );
                                                                                  Navigator.pop(
                                                                                    context,
                                                                                  );
                                                                                },
                                                                              );
                                                                              _saveBills();
                                                                            },
                                                                            icon: Icon(
                                                                              Icons.remove_circle,
                                                                              fontWeight: FontWeight.bold,
                                                                              color: Colors.red,
                                                                            ),
                                                                            label: Text(
                                                                              "Yes",
                                                                              style: TextStyle(
                                                                                fontWeight: FontWeight.bold,
                                                                                color: Colors.red,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                              );
                                                            },
                                                            icon: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              color: Colors
                                                                  .redAccent,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                const SizedBox(height: 20 * 2),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.all(20),
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.all(20),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: uploading ? null : _uploadBills,
                        child: const Text(
                          "Upload Bills",
                          style: TextStyle(
                            fontSize: 17,
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
      ),
    );
  }
}
