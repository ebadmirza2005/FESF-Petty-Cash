import 'dart:convert';
// import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UploadedBills extends StatefulWidget {
  const UploadedBills({super.key});

  @override
  State<UploadedBills> createState() => _UploadedBillsState();
}

class _UploadedBillsState extends State<UploadedBills> {
  List<Map<String, dynamic>> _uploadedBills = [];

  @override
  void initState() {
    super.initState();
    _loadUploadedBills();
  }

  Future<void> _loadUploadedBills() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('uploadedBillsData');
    if (data != null) {
      final decoded = jsonDecode(data);
      setState(() {
        _uploadedBills = List<Map<String, dynamic>>.from(decoded);
      });
    }
  }

  Future<void> _saveUploadedBills() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uploadedBillsData', jsonEncode(_uploadedBills));
  }

  void removeBill(int index) async {
    setState(() {
      _uploadedBills.removeAt(index);
    });
    await _saveUploadedBills(); // ✅ remove hone ke baad SharedPreferences update
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Uploaded Bills"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _uploadedBills.isEmpty
          ? const Center(
              child: Text(
                "No uploaded bills found.",
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: _uploadedBills.length,
              itemBuilder: (context, i) {
                final bill = _uploadedBills[i];
                final expenseHead = bill['expenseHead']?['name'] ?? 'N/A';
                final date = bill['date'] ?? 'N/A';
                final narration = bill['narration'] ?? 'N/A';
                final amount = bill['amount'] ?? 'N/A';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 3,
                  child: ListTile(
                    title: Text(
                      expenseHead,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Date: $date"),
                        Text("Amount: Rs. $amount"),
                        Text("Narration: $narration"),
                        const SizedBox(height: 6),
                        Text(
                          "Uploaded",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        // ElevatedButton(
                        //   onPressed: () {},
                        //   // onPressed: () => _removeBill(i),
                        //   style: ElevatedButton.styleFrom(
                        //     backgroundColor: Colors.red.shade50,
                        //   ),
                        //   child: const Text(
                        //     "Uploaded",
                        //     style: TextStyle(color: Colors.green),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
