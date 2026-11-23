import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() => runApp(const BroderieApp());

class BroderieApp extends StatelessWidget {
  const BroderieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Broderie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFC9A227),
      ),
      home: const HomeScreen(),
    );
  }
}
