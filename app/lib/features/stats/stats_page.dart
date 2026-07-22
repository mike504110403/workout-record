import 'package:flutter/material.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('數據')),
      body: const Center(
        child: Text('數據', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
