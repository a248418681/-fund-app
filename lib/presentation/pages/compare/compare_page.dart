import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ComparePage extends StatelessWidget {
  const ComparePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
          title: const Text('基金对比'), backgroundColor: AppTheme.bgSecondary),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.compare_arrows, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('基金对比',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('选择多只基金进行收益、风险等多维度对比',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
