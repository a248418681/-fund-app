import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class BacktestPage extends StatelessWidget {
  const BacktestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
          title: const Text('回测模拟'), backgroundColor: AppTheme.bgSecondary),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('回测模拟',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('模拟定投、择时策略的历史回测',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
