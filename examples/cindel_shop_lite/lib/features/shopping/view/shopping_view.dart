import 'package:flutter/material.dart';

class ShoppingView extends StatelessWidget {
  const ShoppingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping'),
      ),
      body: const Center(
        child: Text('Shopping View'),
      ),
    );
  }
}
