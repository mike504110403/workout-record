import 'package:flutter/material.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歷史')),
      body: const Center(
        child: Text('歷史', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
