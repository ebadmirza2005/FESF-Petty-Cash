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

  const BillScreen({
    super.key,
    required this.name,
    required this.locationCode,
    this.imageFile,
  });

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  double _balance = 0.0, _openingBalance = 0.0;
  String _reportingPeriod = 'Loading...';
  DateTime? balanceUpdatedAt;

  bool _isRefreshing = false;
  bool _isLoadingOpening = false;
  bool _isLoadingReport = false;

  @override
  void initState() {
    super.initState();
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
      // silent fail (optional: show snackbar)
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
          IconButton(
            icon: const Icon(Icons.logout, size: 28),
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Balance
            _infoCard(
              'Current Balance',
              Row(
                children: [
                  if (_isRefreshing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text('Rs. ${NumberFormat('#,###').format(_balance)}'),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _fetchBalance,
                  ),
                ],
              ),
            ),

            // Opening Balance
            _infoCard(
              'Opening Balance',
              Row(
                children: [
                  if (_isLoadingOpening)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      'Rs. ${NumberFormat('#,###').format(_openingBalance)}',
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () async {
                      setState(() => _isLoadingOpening = true);
                      await _fetchReportingPeriod();
                      setState(() => _isLoadingOpening = false);
                    },
                  ),
                ],
              ),
            ),

            // Reporting Period
            _infoCard(
              'Reporting Period',
              Row(
                children: [
                  if (_isLoadingReport)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    SizedBox(
                      width: 160,
                      child: Text(
                        _reportingPeriod,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () async {
                      setState(() => _isLoadingReport = true);
                      await _fetchReportingPeriod();
                      setState(() => _isLoadingReport = false);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),
            Column(
              children: [
                SizedBox(
                  height: 300,
                  child: Center(
                    child: widget.imageFile != null
                        ? Image.file(widget.imageFile!, height: 250)
                        : SizedBox(
                            child: const Text(
                              "No Bill Preview",
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddBill()),
                ),
                child: const Text(
                  "Add Bill",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
