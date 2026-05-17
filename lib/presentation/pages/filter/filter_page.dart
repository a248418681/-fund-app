import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class FilterPage extends StatelessWidget {
  const FilterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(title: const Text('基金筛选'), backgroundColor: AppTheme.bgSecondary),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('基金筛选', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('按类型、规模、收益率等条件筛选基金', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
