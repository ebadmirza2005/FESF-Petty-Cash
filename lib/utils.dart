import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TextWidget extends StatelessWidget {
  final String text;
  const TextWidget({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }
}

// Card Widget

class CardWidget extends StatelessWidget {
  final String text;
  final bool loading;
  final double balance;
  const CardWidget({
    super.key,
    required this.text,
    required this.loading,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 10),
                loading
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      )
                    : Text(
                        'Rs. ${NumberFormat('#,###').format(balance)}',
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
    );
  }
}

class AlertWidget extends StatefulWidget {
  final String text;
  final String contentText;
  final String btnText1;
  final String btnText2;
  final VoidCallback onFunction;
  const AlertWidget({
    super.key,
    required this.text,
    required this.contentText,
    required this.btnText1,
    required this.btnText2,
    required this.onFunction,
  });

  @override
  State<AlertWidget> createState() => _AlertWidgetState();
}

class _AlertWidgetState extends State<AlertWidget> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Center(
        child: Text(
          widget.text,
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),
      ),
      content: Text(widget.contentText),
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
            widget.btnText1,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ),
        SizedBox(width: 41),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          onPressed: widget.onFunction,
          icon: Icon(
            Icons.logout,
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
          label: Text(
            widget.btnText2,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
      ],
    );
  }
}
