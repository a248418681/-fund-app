import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/di/injection.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../bloc/sector_detail/sector_detail_bloc.dart';
import '../../bloc/sector_detail/sector_detail_event.dart';
import '../../bloc/sector_detail/sector_detail_state.dart';

class SectorDetailPage extends StatelessWidget {
  final String code;
  final SectorRankItem? sector;

  const SectorDetailPage({super.key, required this.code, this.sector});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SectorDetailBloc(
        getIt<FundRepository>(),
      )..add(SectorDetailLoad(
          code: code,
          name: sector?.name ?? '',
          price: sector?.price ?? 0,
          changePercent: sector?.changePercent ?? 0,
          change: sector?.change ?? 0,
        )),
      child: const _SectorDetailView(),
    );
  }
}

class _SectorDetailView extends StatelessWidget {
  const _SectorDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SectorDetailBloc, SectorDetailState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppTheme.bgSecondary,
            title: Text(
              state.sectorName.isNotEmpty ? state.sectorName : '板块详情',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          body: _buildBody(context, state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, SectorDetailState state) {
    if (state.status == SectorDetailStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == SectorDetailStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(state.errorMessage ?? '加载失败',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.read<SectorDetailBloc>().add(SectorDetailLoad(
                    code: state.sectorCode,
                    name: state.sectorName,
                    price: state.sectorPrice,
                    changePercent: state.sectorChangePercent,
                    change: state.sectorChange,
                  )),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final isUp = state.sectorChangePercent >= 0;
    final color = isUp ? AppTheme.upColor : AppTheme.downColor;

    return ListView(
      children: [
        // ── 顶部概览卡片 ──
        _buildHeaderCard(state, color),
        const SizedBox(height: 20),
        // ── 成分股区域 ──
        _buildSectionHeader(
          title: '成分股',
          count: state.stocks.length,
          icon: Icons.bar_chart_outlined,
        ),
        const SizedBox(height: 8),
        _buildConstituentHeader(),
        ..._buildConstituentList(state),
        const SizedBox(height: 24),
        // ── 相关基金区域 ──
        if (state.funds.isNotEmpty) ...[
          _buildSectionHeader(
            title: '相关基金',
            count: state.funds.length,
            icon: Icons.account_balance_wallet_outlined,
            subtitle: state.funds.where((f) => f.hasEstimate).isNotEmpty
                ? '${state.funds.where((f) => f.hasEstimate).length} 只有估值'
                : null,
          ),
          const SizedBox(height: 8),
          ..._buildFundList(context, state),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  // ── 通用区块标题 ──
  Widget _buildSectionHeader({
    required String title,
    required int count,
    required IconData icon,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }

  // ── 顶部概览卡片 ──
  Widget _buildHeaderCard(SectorDetailState state, Color color) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(state.sectorName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(state.sectorCode,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                state.sectorPrice > 0 ? state.sectorPrice.toStringAsFixed(2) : '--',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${state.sectorChangePercent >= 0 ? '+' : ''}${state.sectorChangePercent.toStringAsFixed(2)}%',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                    ),
                    Text(
                      '${state.sectorChange >= 0 ? '+' : ''}${state.sectorChange.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 成分股表头 ──
  Widget _buildConstituentHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
          Expanded(flex: 3, child: Text('名称/代码', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
          Expanded(flex: 2, child: Text('现价', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('涨跌幅', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // ── 成分股列表 ──
  List<Widget> _buildConstituentList(SectorDetailState state) {
    if (state.stocks.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: Text('暂无成分股数据', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          ),
        ),
      ];
    }

    final sorted = List<SectorConstituentItem>.from(state.stocks)
      ..sort((a, b) => b.changePercent.compareTo(a.changePercent));

    return sorted.asMap().entries.map((entry) {
      final idx = entry.key;
      final stock = entry.value;
      final isUp = stock.changePercent >= 0;
      final sColor = isUp ? AppTheme.upColor : AppTheme.downColor;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('${idx + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: idx < 3 ? AppTheme.primary : AppTheme.textMuted,
                  )),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stock.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(stock.code,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(stock.price.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${stock.changePercent >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sColor),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ── 基金列表（可点击跳转详情） ──
  List<Widget> _buildFundList(BuildContext context, SectorDetailState state) {
    return state.funds.asMap().entries.map((entry) {
      final idx = entry.key;
      final fund = entry.value;
      final isUp = fund.estimateChange >= 0;
      final fColor = fund.hasEstimate
          ? (isUp ? AppTheme.upColor : AppTheme.downColor)
          : AppTheme.textMuted;

      return InkWell(
        onTap: () => context.push('/detail/${fund.code}'),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // 排名
              SizedBox(
                width: 28,
                child: Text('${idx + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: idx < 3 ? AppTheme.primary : AppTheme.textMuted,
                    )),
              ),
              // 名称 + 代码 + 类型标签
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(fund.name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(fund.code,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        if (fund.type.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _buildTypeTag(fund.type),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 净值
              Expanded(
                flex: 2,
                child: Text(
                  fund.netValue > 0 ? fund.netValue.toStringAsFixed(4) : '--',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fund.netValue > 0 ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                ),
              ),
              // 估算涨跌幅
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: fColor.withValues(alpha: fund.hasEstimate ? 0.1 : 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    fund.hasEstimate
                        ? '${fund.estimateChange >= 0 ? '+' : ''}${fund.estimateChange.toStringAsFixed(2)}%'
                        : '暂无',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: fund.hasEstimate ? FontWeight.w600 : FontWeight.w400,
                      color: fColor,
                    ),
                  ),
                ),
              ),
              // 跳转箭头
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ── 基金类型标签 ──
  Widget _buildTypeTag(String type) {
    Color bgColor;
    Color textColor;
    String label;

    if (type.contains('指数')) {
      bgColor = Colors.blue.withValues(alpha: 0.08);
      textColor = Colors.blue;
      label = '指数';
    } else if (type.contains('混合')) {
      bgColor = Colors.orange.withValues(alpha: 0.08);
      textColor = Colors.orange;
      label = '混合';
    } else if (type.contains('QDII') || type.contains('海外')) {
      bgColor = Colors.purple.withValues(alpha: 0.08);
      textColor = Colors.purple;
      label = 'QDII';
    } else if (type.contains('债券') || type.contains('债')) {
      bgColor = Colors.green.withValues(alpha: 0.08);
      textColor = Colors.green;
      label = '债券';
    } else if (type.contains('股票')) {
      bgColor = Colors.red.withValues(alpha: 0.08);
      textColor = Colors.red.shade700;
      label = '股票';
    } else if (type.contains('FOF')) {
      bgColor = Colors.teal.withValues(alpha: 0.08);
      textColor = Colors.teal;
      label = 'FOF';
    } else {
      bgColor = AppTheme.textMuted.withValues(alpha: 0.08);
      textColor = AppTheme.textMuted;
      label = type.length > 4 ? type.substring(0, 4) : type;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: textColor, fontWeight: FontWeight.w500)),
    );
  }
}
