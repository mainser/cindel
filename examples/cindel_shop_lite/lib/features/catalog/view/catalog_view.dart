import 'package:flutter/material.dart';

class CatalogView extends StatelessWidget {
  const CatalogView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog'),
      ),
      body: const Center(
        child: Text('Catalog View'),
      ),
    );
  }
}
