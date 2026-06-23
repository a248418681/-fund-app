import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../bloc/holdings/holdings_bloc.dart';
import '../../bloc/holdings/holdings_event.dart';
import '../../bloc/holdings/holdings_state.dart';
import '../../../domain/entities/fund_entity.dart';

/// 安全解析收益率字符串（可能含 % + - 符号）
double _parseProfitRate(String? raw) {
  if (raw == null || raw.isEmpty) return 0;
  final cleaned = raw.replaceAll('%', '').replaceAll('+', '').trim();
  return double.tryParse(cleaned) ?? 0;
}

class AnalysisPage extends StatelessWidget {
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('收益分析'),
        backgroundColor: AppTheme.bgSecondary,
        actions: [
          IconButton(
            icon: const Icon(Icons.trending_up),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<HoldingsBloc>().add(HoldingsRefresh());
        },
        child: BlocBuilder<HoldingsBloc, HoldingsState>(
          builder: (ctx, state) {
            if (state.status == HoldingsStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.holdings.isEmpty) {
              return _buildEmpty();
            }

            final summary = state.summary;
            final holdings = state.holdings;

            // 按收益率排序
            final sortedByProfit = List.of(holdings)
              ..sort((a, b) {
                final pa = _parseProfitRate(a.profitRate);
                final pb = _parseProfitRate(b.profitRate);
                return pb.compareTo(pa);
              });

            // 按金额排序
            final sortedByAmount = List.of(holdings)
              ..sort((a, b) => b.marketValue.compareTo(a.marketValue));

            // 按类型分组
            final typeMap = <String, double>{};
            for (final h in holdings) {
              final type = h.fundType ?? '混合型';
              typeMap[type] = (typeMap[type] ?? 0) + h.marketValue;
            }
            final sortedTypes = typeMap.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            final upCount = holdings
                .where((h) => _parseProfitRate(h.profitRate) >= 0)
                .length;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 总览卡片
                  _buildOverviewCard(summary, upCount, holdings.length),
                  const SizedBox(height: 20),

                  // 收益率排行
                  _buildSectionTitle('收益排行'),
                  const SizedBox(height: 10),
                  _buildProfitLeaderboard(sortedByProfit.take(5).toList()),
                  const SizedBox(height: 20),

                  // 持仓分布
                  _buildSectionTitle('持仓分布'),
                  const SizedBox(height: 10),
                  _buildTypeDistribution(sortedTypes),
                  const SizedBox(height: 20),

                  // 持仓明细（按金额排序）
                  _buildSectionTitle('持仓明细（按金额）'),
                  const SizedBox(height: 10),
                  _buildHoldingsDetail(sortedByAmount, holdings),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_outlined,
              size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('暂无持仓数据',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('添加基金后查看收益分析',
              style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(HoldingSummary s, int upCount, int totalCount) {
    final isUp = s.totalProfit >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUp
              ? [const Color(0xFFe4393c), const Color(0xFFe57373)]
              : [const Color(0xFF18a058), const Color(0xFF52c99a)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: (isUp ? AppTheme.upColor : AppTheme.downColor)
                  .withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('持仓总览',
              style: TextStyle(
                  fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('总收益',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Text(
                      '${isUp ? '+' : ''}¥${s.totalProfit.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('收益率',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Text(
                      '${(s.totalProfitRate * 100).toStringAsFixed(2)}%',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statPill('总市值', '¥${s.totalValue.toStringAsFixed(0)}',
                  Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 8),
              _statPill('总成本', '¥${s.totalCost.toStringAsFixed(0)}',
                  Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 8),
              _statPill('盈利', '$upCount/$totalCount只',
                  Colors.white.withValues(alpha: 0.2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary));
  }

  Widget _buildProfitLeaderboard(List holdings) {
    return Column(
      children: holdings.asMap().entries.map((e) {
        final idx = e.key;
        final h = e.value;
        final rate = _parseProfitRate(h.profitRate);
        final isUp = rate >= 0;
        final color = idx == 0
            ? Colors.amber
            : (isUp ? AppTheme.upColor : AppTheme.downColor);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            borderRadius: BorderRadius.circular(10),
            border: idx == 0
                ? Border.all(
                    color: Colors.amber.withValues(alpha: 0.3), width: 1)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: idx < 3
                      ? Colors.amber.withValues(alpha: 0.1)
                      : AppTheme.bgPrimary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('${idx + 1}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: idx < 3 ? Colors.amber : AppTheme.textMuted)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    Text(h.code,
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isUp ? '+' : ''}${rate.toStringAsFixed(2)}%',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                  Text(
                    '${isUp ? '+' : ''}¥${h.profit.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 11, color: color.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypeDistribution(List<MapEntry<String, double>> types) {
    final total = types.fold<double>(0, (sum, e) => sum + e.value);
    if (total == 0) return const SizedBox.shrink();

    final colors = [
      AppTheme.primary,
      AppTheme.upColor,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.grey
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 水平条
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: types.asMap().entries.map((e) {
                final ratio = e.value.value / total;
                return Expanded(
                  flex: (ratio * 100).round().clamp(1, 100),
                  child: Container(
                    height: 10,
                    color: colors[e.key % colors.length],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // 图例
          ...types.asMap().entries.map((e) {
            final ratio = e.value.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[e.key % colors.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(e.value.key,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textPrimary)),
                  const Spacer(),
                  Text('¥${e.value.value.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${(ratio * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              AppTheme.textSecondary.withValues(alpha: 0.7))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHoldingsDetail(List holdings, List allHoldings) {
    final total = allHoldings.fold<double>(0.0, (s, x) => s + x.marketValue);
    return Column(
      children: holdings.map((h) {
        final rate = _parseProfitRate(h.profitRate);
        final isUp = rate >= 0;
        final ratio = total > 0 ? h.marketValue / total : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(
                            '${h.code} · ${(ratio * 100).toStringAsFixed(1)}% 仓位',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary
                                    .withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('¥${h.marketValue.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${isUp ? '+' : ''}¥${h.profit.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: isUp
                                  ? AppTheme.upColor
                                  : AppTheme.downColor)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 简单柱状图表示占比
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  backgroundColor: AppTheme.bgPrimary,
                  valueColor: AlwaysStoppedAnimation(isUp
                      ? AppTheme.upColor.withValues(alpha: 0.7)
                      : AppTheme.downColor.withValues(alpha: 0.7)),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
