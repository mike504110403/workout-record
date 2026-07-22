import 'package:flutter/material.dart';

class WorkoutPage extends StatelessWidget {
  const WorkoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('訓練')),
      body: const Center(
        child: Text('訓練', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
