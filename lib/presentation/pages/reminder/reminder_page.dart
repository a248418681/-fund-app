import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ReminderPage extends StatelessWidget {
  const ReminderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(title: const Text('智能提醒'), backgroundColor: AppTheme.bgSecondary),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_outlined, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('智能提醒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('设置基金估值提醒，及时把握交易机会', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
