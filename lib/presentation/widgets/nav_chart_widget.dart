import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/fund_entity.dart';

/// 净值走势图组件（基于 fl_chart）
class NavChartWidget extends StatelessWidget {
  final List<NetValueRecord> history;
  final Color? lineColor;

  const NavChartWidget({
    super.key,
    required this.history,
    this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(child: Text('暂无数据', style: TextStyle(color: AppTheme.textMuted)));
    }

    final spots = history.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), e.value.netValue)
    ).toList();

    if (spots.length < 2) {
      return const Center(child: Text('数据不足', style: TextStyle(color: AppTheme.textMuted)));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;

    // 判断整体趋势颜色
    final isUpOverall = spots.last.y >= spots.first.y;
    final trendColor = isUpOverall ? AppTheme.upColor : AppTheme.downColor;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: range / 4,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppTheme.borderLight,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY - range * 0.08,
        maxY: maxY + range * 0.08,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.x.toInt();
              final record = idx < history.length ? history[idx] : null;
              return LineTooltipItem(
                '${record?.date ?? ''}\n${s.y.toStringAsFixed(4)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: trendColor,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  trendColor.withValues(alpha: 0.2),
                  trendColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
