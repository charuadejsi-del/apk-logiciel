import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const BroderieApp());

class BroderieApp extends StatelessWidget {
  const BroderieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Broderie',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
