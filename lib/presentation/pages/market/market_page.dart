import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../bloc/market/market_bloc.dart';
import '../../bloc/market/market_event.dart';
import '../../bloc/market/market_state.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  // ── 基金类型映射 ──
  static const _fundTypes = [
    ('all', '全部'),
    ('gp', '股票型'),
    ('hh', '混合型'),
    ('zq', '债券型'),
    ('zs', '指数型'),
    ('qdii', 'QDII'),
  ];

  @override
  void initState() {
    super.initState();
    context.read<MarketBloc>().add(MarketLoad());
  }

  // 打开外部链接（指数/板块详情）
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('行情'),
        backgroundColor: AppTheme.bgSecondary,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索基金',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: '高级筛选',
            onPressed: () => context.push('/filter'),
          ),
        ],
      ),
      body: BlocBuilder<MarketBloc, MarketState>(
        builder: (context, state) {
          if (state.status == MarketStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == MarketStatus.error) {
            return _buildError(state.errorMessage ?? '加载失败');
          }

          return RefreshIndicator(
            onRefresh: () async {
              final bloc = context.read<MarketBloc>();
              bloc.add(MarketRefresh());
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: CustomScrollView(
              slivers: [
                _buildIndexCards(state.indices),
                _buildFundTypeChips(state.fundType),
                _buildSectorCards(state.sectors),
                _buildSortBar(state),
                _buildRankings(state),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ────────────────────── 错误页 ──────────────────────
  Widget _buildError(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.read<MarketBloc>().add(MarketLoad()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ────────────────────── 1. 大盘指数（横向滚动） ──────────────────────
  Widget _buildIndexCards(List<MarketIndex> indices) {
    if (indices.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('主要指数', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('实时', style: TextStyle(fontSize: 10, color: AppTheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: indices.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final i = indices[idx];
                  final isUp = i.change >= 0;
                  final color = isUp ? AppTheme.upColor : AppTheme.downColor;
                  return GestureDetector(
                    onTap: () => _openUrl('https://quote.eastmoney.com/zs${i.code.substring(2)}.html'),
                    child: Container(
                      width: 146,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSecondary,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(i.name, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                i.current.toStringAsFixed(2),
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '${isUp ? '+' : ''}${i.changeRate.toStringAsFixed(2)}%',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────── 2. 基金类型 Chips ──────────────────────
  Widget _buildFundTypeChips(String selectedType) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _fundTypes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, idx) {
            final ft = _fundTypes[idx];
            final isSelected = selectedType == ft.$1;
            return GestureDetector(
              onTap: () {
                if (!isSelected) {
                  context.read<MarketBloc>().add(MarketChangeFundType(ft.$1));
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : AppTheme.bgSecondary,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Text(
                  ft.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ────────────────────── 3. 热门板块排行 ──────────────────────
  Widget _buildSectorCards(List<SectorRankItem> sectors) {
    if (sectors.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('热门板块', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sectors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final s = sectors[idx];
                  final isUp = s.changePercent >= 0;
                  final color = isUp ? AppTheme.upColor : AppTheme.downColor;
                  return GestureDetector(
                    onTap: () => context.push('/sector/${s.code}', extra: s),
                    child: Container(
                      width: 110,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSecondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            s.price.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          Row(
                            children: [
                              Icon(
                                isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                size: 16,
                                color: color,
                              ),
                              Text(
                                '${s.changePercent.toStringAsFixed(2)}%',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────── 4. 排序栏 ──────────────────────
  Widget _buildSortBar(MarketState state) {
    const sorts = [
      ('r', '日涨跌'),
      ('zzf', '周涨跌'),
      ('1yzf', '月涨跌'),
      ('3yzf', '三月'),
      ('6yzf', '半年'),
      ('1nzf', '年涨跌'),
    ];

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 4),
              child: Icon(Icons.sort, size: 16, color: AppTheme.textMuted),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sorts.map((s) {
                    final isSelected = state.sortType == s.$1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: GestureDetector(
                        onTap: () {
                          final newOrder = isSelected
                              ? (state.order == 'desc' ? 'asc' : 'desc')
                              : 'desc';
                          context.read<MarketBloc>().add(MarketChangeSort(s.$1, newOrder));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 2),
                                Icon(
                                  state.order == 'desc' ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────── 5. 基金排行列表 ──────────────────────
  Widget _buildRankings(MarketState state) {
    if (state.isRefreshing && state.rankings.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      );
    }

    if (state.rankings.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 36, color: AppTheme.textMuted),
                SizedBox(height: 8),
                Text('暂无排行数据', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, idx) {
            final item = state.rankings[idx];
            return _RankItemTile(
              rank: idx + 1,
              item: item,
              onTap: () => context.push('/detail/${item.code}'),
            );
          },
          childCount: state.rankings.length,
        ),
      ),
    );
  }
}

// ═══════════════════════ 排行项组件 ═══════════════════════
class _RankItemTile extends StatelessWidget {
  final int rank;
  final FundRankItem item;
  final VoidCallback onTap;

  const _RankItemTile({required this.rank, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUp = item.dayChange >= 0;
    final color = isUp ? AppTheme.upColor : AppTheme.downColor;

    final rankColor = rank == 1
        ? const Color(0xFFFF6B35)
        : rank == 2
            ? const Color(0xFF999999)
            : rank == 3
                ? const Color(0xFFCD853F)
                : null;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: rankColor != null
                  ? Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: rankColor,
                        ),
                      ),
                    )
                  : Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.code} · ${item.type}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.netValue.toStringAsFixed(4),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${isUp ? '+' : ''}${item.dayChange.toStringAsFixed(2)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
