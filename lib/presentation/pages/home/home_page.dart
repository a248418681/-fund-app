import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../bloc/home/home_bloc.dart';
import '../../bloc/home/home_event.dart';
import '../../bloc/home/home_state.dart';
import '../../bloc/search/search_bloc.dart';
import '../../widgets/fund_search_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    context.read<HomeBloc>().add(HomeInit());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: BlocBuilder<HomeBloc, HomeState>(
          builder: (context, state) {
            if (state.status == HomeStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: () async =>
                  context.read<HomeBloc>().add(HomeRefresh()),
              child: CustomScrollView(
                slivers: [
                  _buildHeader(context),
                  _buildNoticeBar(),
                  _buildMarketOverview(state),
                  _buildQuickActions(context),
                  _buildNewsSection(state),
                  _buildWatchlistSection(context, state),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.bgSecondary, AppTheme.bgPrimary],
          ),
        ),
        child: Row(
          children: [
            const Text('基金宝',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                )),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () => context.push('/news'),
              iconSize: 22,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
              iconSize: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeBar() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderColor, width: 0.5),
        ),
        child: const Row(
          children: [
            Icon(Icons.volume_up, size: 14, color: AppTheme.textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '基金投资有风险，入市需谨慎 | 交易时间：工作日 9:30-15:00',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketOverview(HomeState state) {
    if (state.indices.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isTrading()
                            ? AppTheme.downColor
                            : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('大盘指数',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isTrading()
                        ? AppTheme.downColor.withValues(alpha: 0.1)
                        : AppTheme.bgPrimary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isTrading() ? '交易中' : '已收盘',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isTrading()
                          ? AppTheme.downColor
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: state.indices.length,
              itemBuilder: (context, idx) {
                final index = state.indices[idx];
                final isUp = index.change >= 0;
                return InkWell(
                  onTap: () => context.go('/market'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.bgPrimary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isUp
                            ? AppTheme.upColor.withValues(alpha: 0.2)
                            : AppTheme.downColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(index.name,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary)),
                        Text(
                          index.current.toStringAsFixed(2),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color:
                                  isUp ? AppTheme.upColor : AppTheme.downColor),
                        ),
                        Text(
                          '${isUp ? '+' : ''}${index.changeRate.toStringAsFixed(2)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  isUp ? AppTheme.upColor : AppTheme.downColor),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isTrading() {
    final now = DateTime.now();
    if (now.weekday == 6 || now.weekday == 7) return false;
    final mins = now.hour * 60 + now.minute;
    return (mins >= 570 && mins < 690) || (mins >= 780 && mins < 900);
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      ('搜索', Icons.search, () => _showSearchSheet(context)),
      ('对比', Icons.compare_arrows, () => context.push('/compare')),
      ('回测', Icons.show_chart, () => context.push('/backtest')),
      ('提醒', Icons.notifications_outlined, () => context.push('/reminder')),
    ];

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('快捷功能',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.2,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: actions.length,
              itemBuilder: (context, idx) {
                final (label, icon, fn) = actions[idx];
                return InkWell(
                  onTap: fn,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsSection(HomeState state) {
    if (state.news.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('财经资讯',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  GestureDetector(
                    onTap: () => context.push('/news'),
                    child: const Text('更多 >',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.primary)),
                  ),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.news.length > 5 ? 5 : state.news.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 14, endIndent: 14),
              itemBuilder: (context, idx) {
                final news = state.news[idx];
                return ListTile(
                  dense: true,
                  title: Text(
                    news.title,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${news.source} · ${news.time}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onTap: () => context.push('/news'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistSection(BuildContext context, HomeState state) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.lastRefreshTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('最后刷新: ${state.lastRefreshTime}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
              ),
            if (state.watchlist.isEmpty)
              _buildEmptyWatchlist(context)
            else
              ...state.watchlist
                  .map((item) => _buildWatchlistItem(context, item)),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWatchlist(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.search, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          const Text('暂无自选基金',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showSearchSheet(context),
            child: const Text('添加基金'),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistItem(BuildContext context, WatchlistItem item) {
    final change = double.tryParse(item.estimateChange ?? '0') ?? 0;
    final isUp = change > 0;
    final isFlat = change == 0;

    return InkWell(
      onTap: () => context.push('/detail/${item.code}'),
      onLongPress: () => _showAlertDialog(context, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(item.name.isEmpty ? item.code : item.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: item.dataSource == 'nav'
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          item.dataSource == 'nav' ? '净值' : '估值',
                          style: TextStyle(
                              fontSize: 9,
                              color: item.dataSource == 'nav'
                                  ? Colors.blue
                                  : Colors.orange),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.code,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.estimateValue ?? '--',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isFlat ? '' : (isUp ? '+' : '')}${item.estimateChange ?? '--'}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isFlat
                        ? AppTheme.flatColor
                        : (isUp ? AppTheme.upColor : AppTheme.downColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAlertDialog(BuildContext context, WatchlistItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设置提醒 - ${item.name}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('涨到目标值'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.trending_down),
              title: const Text('跌到目标值'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.show_chart),
              title: const Text('涨幅提醒'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除自选', style: TextStyle(color: Colors.red)),
              onTap: () {
                context.read<HomeBloc>().add(HomeRemoveWatchlist(item.code));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider(
        create: (_) => getIt<SearchBloc>(),
        child: const FundSearchSheet(),
      ),
    );
  }
}
