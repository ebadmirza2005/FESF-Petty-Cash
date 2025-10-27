import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  bool _loadingBalance = false, _loadingReport = false;
  Map<String, dynamic>? _savedBillData;
  File? _savedImageFile;

  @override
  void initState() {
    super.initState();
    _loadSavedBill();
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
    setState(() => _loadingReport = true);
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
      setState(() => _reportingPeriod = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loadingReport = false);
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

  Future<void> _uploadBill() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      _showSnack("Auth token missing.");
      return;
    }

    final data = widget.billData ?? _savedBillData;
    final image = widget.imageFile ?? _savedImageFile;
    if (data == null || image == null) {
      _showSnack("No bill data or image found.");
      return;
    }

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
        'expense_head_id': data['expenseHead'] ?? '',
        'amount':
            double.tryParse(
              data['amount']
                  .toString()
                  .replaceAll(
                    RegExp(r'[^0-9.]'),
                    '',
                  ) // sirf digits aur dot allow karega
                  .trim(),
            )?.toString() ??
            '0',

        'date': _formatDate(data['date']),
        if (_reportingPeriodId != null)
          'reporting_period_id': _reportingPeriodId.toString(),
      })
      ..fields.addAll({
        'narration': data['narration'] ?? '',
        'expense_head_id': data['expenseHead'].toString().replaceAll(
          RegExp(r'[^0-9]'),
          '',
        ),
        'amount':
            double.tryParse(
              data['amount']
                  .toString()
                  .replaceAll(RegExp(r'[^0-9.]'), '')
                  .trim(),
            )?.toString() ??
            '0',
        'date': _formatDate(data['date']),
        if (_reportingPeriodId != null)
          'reporting_period_id': _reportingPeriodId.toString(),
      })
      ..files.add(await http.MultipartFile.fromPath('imageFile', image.path));

    print("🟢 Final Data:");
    print({
      'narration': data['narration'],
      'expense_head_id': data['expenseHead'].toString().split('-').first.trim(),

      'amount': double.tryParse(
        data['amount'].toString().replaceAll(RegExp(r'[^0-9.]'), '').trim(),
      )?.toString(),
      'date': _formatDate(data['date']),
      'reporting_period_id': _reportingPeriodId,
      'imageFile': image.path,
    });

    try {
      final res = await req.send();
      final body = await res.stream.bytesToString();

      print("🔹 Server Response Code: ${res.statusCode}");
      print("🔹 Server Response Body: $body");

      if (res.statusCode == 200 || res.statusCode == 201) {
        _showSnack("✅ Bill uploaded successfully");
      } else {
        final err = _parseError(body);
        _showSnack("❌ $err");
      }
    } catch (e) {
      _showSnack("⚠️ Error: $e");
    }

    print('Expense Head Value: ${data['expenseHead']}');

    setState(() {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              BillScreen(name: widget.name, locationCode: widget.locationCode),
        ),
      );
    });
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

  Future<void> _loadSavedBill() async {
    final prefs = await SharedPreferences.getInstance();
    final billData = prefs.getString('billData');
    final imagePath = prefs.getString('billImagePath');
    if (billData != null && imagePath != null) {
      setState(() {
        _savedBillData = jsonDecode(billData);
        _savedImageFile = File(imagePath);
      });
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _infoCard(String title, Widget value) => Card(
    child: ListTile(title: Text(title), trailing: value),
  );

  @override
  Widget build(BuildContext context) {
    final bill = widget.billData ?? _savedBillData;
    final img = widget.imageFile ?? _savedImageFile;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: Text(widget.name),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _infoCard(
              'Current Balance',
              _loadingBalance
                  ? const CircularProgressIndicator()
                  : Text('Rs. ${NumberFormat('#,###').format(_balance)}'),
            ),
            SizedBox(height: 15),
            _infoCard(
              'Opening Balance',
              Text('Rs. ${NumberFormat('#,###').format(_openingBalance)}'),
            ),
            SizedBox(height: 15),

            _infoCard(
              'Reporting Period',
              _loadingReport
                  ? const CircularProgressIndicator()
                  : Text(_reportingPeriod),
            ),
            const SizedBox(height: 50),
            bill != null
                ? Card(
                    elevation: 3,
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      leading: img != null
                          ? Image.file(
                              img,
                              width: 10,
                              height: 20,
                              fit: BoxFit.cover,
                            )
                          : null,
                      title: Text(bill['narration'] ?? ''),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Expense: ${bill['expenseHead'] ?? ''}"),
                          Text("Amount: ${bill['amount'] ?? ''}"),
                          Text("Date: ${bill['date'] ?? ''}"),
                        ],
                      ),
                    ),
                  )
                : const Center(child: Text("No Bill Preview Available")),
            const SizedBox(height: 50),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
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
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    onPressed: _uploadBill,
                    child: const Text(
                      "Upload Bill",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
