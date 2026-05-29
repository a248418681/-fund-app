import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../bloc/detail/detail_bloc.dart';
import '../../bloc/detail/detail_event.dart';
import '../../bloc/detail/detail_state.dart';

class FundDetailPage extends StatefulWidget {
  final String code;

  const FundDetailPage({super.key, required this.code});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    context.read<DetailBloc>().add(DetailLoad(widget.code));
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _tabController.dispose();
    super.dispose();
  }

  /// 启动自动刷新（仅交易时间，每60秒）
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;  // widget 已销毁则跳过
      if (_isTradingTime()) {
        context.read<DetailBloc>().add(DetailRefresh(widget.code));
      }
    });
  }

  /// 停止自动刷新
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 判断当前是否为交易时间
  /// 上午盘：9:30-11:30，下午盘：13:00-15:00
  bool _isTradingTime() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    // 周末休市
    if (weekday == 6 || weekday == 7) return false;
    
    final hour = now.hour;
    final minute = now.minute;
    final timeMinutes = hour * 60 + minute;
    
    // 上午盘：9:30-11:30 (570-690分钟)
    if (timeMinutes >= 570 && timeMinutes < 690) return true;
    
    // 下午盘：13:00-15:00 (780-900分钟)
    if (timeMinutes >= 780 && timeMinutes < 900) return true;
    
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSecondary,
        title: BlocBuilder<DetailBloc, DetailState>(
          buildWhen: (prev, curr) =>
              prev.accurateData?.name != curr.accurateData?.name ||
              prev.accurateData?.code != curr.accurateData?.code,
          builder: (context, state) {
            final name = state.accurateData?.name ?? '';
            final code = state.accurateData?.code ?? widget.code;
            return Row(
              children: [
                Flexible(
                  child: Text(
                    name.isNotEmpty ? name : code,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.star_border, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 22),
            onPressed: () {},
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: '关联板块'),
            Tab(text: '业绩走势'),
            Tab(text: '我的收益'),
          ],
        ),
      ),
      body: BlocBuilder<DetailBloc, DetailState>(
        builder: (context, state) {
          if (state.status == DetailStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == DetailStatus.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('加载失败: ${state.errorMessage}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<DetailBloc>().add(DetailLoad(widget.code)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<DetailBloc>().add(DetailRefresh(widget.code));
              await Future.delayed(const Duration(milliseconds: 800));
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // 顶部概要区（简洁：仅显示基金名称和当日涨幅）
                  _buildHeaderSummary(state),
                  // Tab 内容
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSectorTab(state),
                        _buildPerformanceTab(state),
                        _buildMyReturnTab(state),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 顶部概要区（今日预估涨跌 + 昨日实际涨跌 + 基金名称）
  Widget _buildHeaderSummary(DetailState state) {
    final data = state.accurateData;

    // 今日预估涨跌
    final estChg = data?.estimateChange ?? 0;
    final estIsUp = estChg >= 0;
    final estIsFlat = estChg == 0;

    // 昨日实际涨跌
    final dayChg = data?.dayChange ?? 0;
    final dayIsUp = dayChg >= 0;
    final dayIsFlat = dayChg == 0;

    Widget chgText(double v, bool up, bool flat, {double size = 22}) {
      return Text(
        '${flat ? '' : (up ? '+' : '')}${v.toStringAsFixed(2)}%',
        style: TextStyle(
          fontSize: size,
          fontWeight: size >= 22 ? FontWeight.bold : FontWeight.w600,
          color: flat ? AppTheme.textSecondary : (up ? AppTheme.upColor : AppTheme.downColor),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.bgSecondary,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧：今日预估 + 昨日实际（纵向排列）
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 今日预估涨跌（大字 + 标签）
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  chgText(estChg, estIsUp, estIsFlat),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text('今日预估', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // 昨日实际涨跌（小字参考）
              Row(
                children: [
                  const Text('昨日 ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  chgText(dayChg, dayIsUp, dayIsFlat, size: 12),
                ],
              ),
            ],
          ),
          const Spacer(),
          // 右侧：基金全称
          if (data?.name != null)
            Flexible(
              child: Text(
                data!.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Tab 1: 关联板块（当日走势 → 行业分布 → 重仓股）
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildSectorTab(DetailState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当日走势（实时更新）
          _buildTodayCard(state),
          const SizedBox(height: 16),
          // 行业分布
          _buildIndustryCard(state.industryAllocation),
          const SizedBox(height: 16),
          // 重仓股
          _buildStockHoldingsCard(state),
        ],
      ),
    );
  }

  // 当日走势卡片（实时估算净值 + 迷你折线图）
  Widget _buildTodayCard(DetailState state) {
    final d = state.accurateData;
    final estimateChange = d?.estimateChange ?? 0;
    final estimate = d?.estimate ?? 0;
    final isUp = estimateChange >= 0;
    final isFlat = estimateChange == 0;
    // 用 navHistory 最近30条画迷你走势图
    final navHistory = state.navHistory;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '当日走势',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                d?.estimateTime ?? '--',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                estimate != 0 ? estimate.toStringAsFixed(4) : '--',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                estimateChange != 0
                    ? '${estimateChange >= 0 ? '+' : ''}${estimateChange.toStringAsFixed(2)}%'
                    : '--',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isFlat
                      ? AppTheme.textSecondary
                      : (isUp ? AppTheme.upColor : AppTheme.downColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 迷你走势图（用历史净值）
          if (navHistory.isNotEmpty)
            SizedBox(
              height: 60,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: navHistory.asMap().entries.map((e) {
                        return FlSpot(e.key.toDouble(), e.value.netValue);
                      }).toList(),
                      isCurved: true,
                      color: isFlat
                          ? AppTheme.textSecondary
                          : (isUp ? AppTheme.upColor : AppTheme.downColor),
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (isFlat
                            ? AppTheme.textSecondary
                            : (isUp ? AppTheme.upColor : AppTheme.downColor))
                            .withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(
              height: 60,
              child: Center(
                child: Text('暂无走势数据',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIndustryCard(List<IndustryAllocation> industries) {
    if (industries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '行业分布',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...industries.map((ind) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      ind.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: AppTheme.borderColor,
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (ind.percent / 100).clamp(0, 1),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: _parseColor(ind.color ?? '#1E88E5'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 45,
                    child: Text(
                      '${ind.percent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStockHoldingsCard(DetailState state) {
    final holdings = state.stockHoldings;
    if (holdings.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '重仓股',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              if (holdings.isNotEmpty)
                Text(
                  '(${holdings.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 表头
          const Row(
            children: [
              Expanded(flex: 2, child: Text('股票', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
              Expanded(flex: 1, child: Text('持仓占比', style: TextStyle(fontSize: 12, color: AppTheme.textMuted), textAlign: TextAlign.right)),
              Expanded(flex: 1, child: Text('涨跌', style: TextStyle(fontSize: 12, color: AppTheme.textMuted), textAlign: TextAlign.right)),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // 持仓列表
          ...holdings.take(10).map((stock) {
            final changePct = stock.changePercent ?? 0;
            final isUp = changePct >= 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stock.stockName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          stock.stockCode,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '${stock.holdingRatio.toStringAsFixed(2)}%',
                      style: const TextStyle(fontSize: 13),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '${isUp ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 13,
                        color: isUp ? AppTheme.upColor : AppTheme.downColor,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Tab 2: 业绩走势（净值图 + 可选期限）
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPerformanceTab(DetailState state) {
    final navHistory = state.navHistory;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 净值图表
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行：净值走势 + 期限选择
                Row(
                  children: [
                    const Text(
                      '净值走势',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    // 期限选择器（横向可滚动）
                    Flexible(child: _buildNavPeriodSelector(state)),
                  ],
                ),
                const SizedBox(height: 8),
                // 时间范围显示
                if (navHistory.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _getNavTimeRange(navHistory),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                const SizedBox(height: 16),
                if (navHistory.isEmpty)
                  const SizedBox(
                    height: 200,
                    child: Center(
                      child: Text('暂无净值数据',
                          style: TextStyle(color: AppTheme.textMuted)),
                    ),
                  )
                else
                  SizedBox(
                    height: 220,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _getNavInterval(navHistory),
                          getDrawingHorizontalLine: (value) => const FlLine(
                            color: AppTheme.borderColor,
                            strokeWidth: 0.5,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: ((navHistory.length - 1) / 4)
                                  .clamp(1, double.infinity),
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= navHistory.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    navHistory[idx].date,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 45,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: AppTheme.textMuted,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: navHistory.asMap().entries.map((e) {
                              return FlSpot(
                                  e.key.toDouble(), e.value.netValue);
                            }).toList(),
                            isCurved: true,
                            color: AppTheme.primary,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppTheme.primary.withValues(alpha: 0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
          ),
          const SizedBox(height: 16),
          // 阶段涨幅（来自 periodReturns）
          _buildPeriodReturnsCard(state.periodReturns),
        ],
      ),
    );
  }

  // 净值走势期限选择器（横向可滚动）
  Widget _buildNavPeriodSelector(DetailState state) {
    final selected = state.selectedNavPeriod;
    const periods = NavPeriod.values;
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: periods.map((period) {
          final isSelected = period == selected;
          return GestureDetector(
            onTap: () {
              final code = state.accurateData?.code ?? '';
              if (code.isNotEmpty) {
                context.read<DetailBloc>().add(DetailChangeNavPeriod(code, period));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                period.label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 阶段涨幅卡片
  Widget _buildPeriodReturnsCard(List<PeriodReturn> periodReturns) {
    if (periodReturns.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '业绩表现',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: periodReturns.map((period) {
              final rate = period.returnRate;
              final isUp = rate >= 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bgPrimary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getPeriodLabel(period),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isUp ? '+' : ''}${rate.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isUp ? AppTheme.upColor : AppTheme.downColor,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _getPeriodLabel(PeriodReturn period) {
    if (period.label.isNotEmpty) return period.label;
    const map = {'1m': '近1月', '3m': '近3月', '6m': '近6月', '1y': '近1年'};
    return map[period.period] ?? period.period;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Tab 3: 我的收益
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildMyReturnTab(DetailState state) {
    final data = state.accurateData;
    // TODO: 接入用户实际持仓数据
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  size: 48,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(height: 12),
                const Text(
                  '我的收益基于您的实际买入记录计算',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                const Text(
                  '当前暂无买入记录，无法展示收益',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                if (data != null)
                  ElevatedButton(
                    onPressed: () {},
                    child: Text('去买入 ${data.name}'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '收益数据每日收盘后更新',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // 工具方法
  // ══════════════════════════════════════════════════════════════════════

  String _getNavTimeRange(List<NetValueRecord> navHistory) {
    if (navHistory.isEmpty) return '';
    final first = navHistory.first.date;
    final last = navHistory.last.date;
    return '$first ~ $last';
  }

  double _getNavInterval(List<NetValueRecord> navHistory) {
    if (navHistory.isEmpty) return 0.1;
    final navs = navHistory.map((e) => e.netValue).toList();
    final max = navs.reduce((a, b) => a > b ? a : b);
    final min = navs.reduce((a, b) => a < b ? a : b);
    final diff = max - min;
    if (diff <= 0) return 0.1;
    return (diff / 4).clamp(0.01, double.infinity);
  }

  Color _parseColor(String hex) {
    final code = hex.replaceAll('#', '').toUpperCase();
    try {
      if (code.length == 6) {
        return Color(int.parse('FF$code', radix: 16));
      }
      if (code.length == 8) {
        return Color(int.parse(code, radix: 16));
      }
    } catch (_) {}
    return AppTheme.primary;
  }
}
