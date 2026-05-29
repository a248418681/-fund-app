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

/// 自选页面 - 只显示用户关注的基金列表
class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  @override
  void initState() {
    super.initState();
    context.read<HomeBloc>().add(HomeInit());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('自选'),
        backgroundColor: AppTheme.bgSecondary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<HomeBloc>().add(HomeRefresh()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSearchSheet(context),
        child: const Icon(Icons.add),
      ),
      body: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          if (state.status == HomeStatus.loading && state.watchlist.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == HomeStatus.error) {
            return _buildErrorState(state.errorMessage ?? '加载失败');
          }

          if (state.watchlist.isEmpty) {
            return _buildEmptyState(context);
          }

          return Column(
            children: [
              if (state.lastRefreshTime.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppTheme.bgSecondary,
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '更新于 ${state.lastRefreshTime}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const Spacer(),
                      if (state.isRefreshing)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              // 表头
              _buildWatchlistHeader(state),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => context.read<HomeBloc>().add(HomeRefresh()),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: state.sortedWatchlist.length,
                    itemBuilder: (context, index) {
                      return _buildWatchlistItem(context, state.sortedWatchlist[index]);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          const Text(
            '加载失败',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              msg,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => context.read<HomeBloc>().add(HomeInit()),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.star_border, size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          const Text(
            '暂无自选基金',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击右下角 + 添加关注的基金',
            style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showSearchSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('添加基金'),
          ),
        ],
      ),
    );
  }

  /// 时间感知的涨跌幅列标签
  String _changeColumnLabel(HomeState state) {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    final weekday = now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    if (isWeekend) return '上日涨跌';
    if (h < 9 || (h == 9 && m < 30)) return '昨日涨跌';
    return '今日涨跌';
  }

  Widget _buildWatchlistHeader(HomeState state) {
    final changeLabel = _changeColumnLabel(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFAFAFA),
      child: Row(
        children: [
          _buildSortHeader('基金名称', 140, WatchlistSortField.name, state),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildSortHeader('估算净值', 80, WatchlistSortField.estimateValue, state),
                const SizedBox(width: 16),
                _buildSortHeader(changeLabel, 72, WatchlistSortField.estimateChange, state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortHeader(String label, double width, WatchlistSortField field, HomeState state) {
    final isActive = state.sortField == field;
    return GestureDetector(
      onTap: () => context.read<HomeBloc>().add(HomeChangeWatchlistSort(field)),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? AppTheme.primary : const Color(0xFF999999),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive)
              Icon(
                state.sortAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 16,
                color: AppTheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistItem(BuildContext context, WatchlistItem item) {
    final change = double.tryParse(item.estimateChange ?? '0') ?? 0;
    final isUp = change > 0;
    final isFlat = change == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderColor, width: 0.5),
      ),
      child: InkWell(
        onTap: () => context.push('/detail/${item.code}'),
        onLongPress: () => _showItemOptions(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name.isEmpty ? item.code : item.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.dataSource == 'nav'
                                ? Colors.blue.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.dataSource == 'nav' ? '净值' : '估值',
                            style: TextStyle(
                              fontSize: 10,
                              color: item.dataSource == 'nav' ? Colors.blue : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.code,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    if (item.estimateTime?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.estimateTime ?? '',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.estimateValue ?? '--',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isFlat ? '' : (isUp ? '+' : '')}${item.estimateChange ?? '--'}%',
                    style: TextStyle(
                      fontSize: 14,
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
      ),
    );
  }

  void _showItemOptions(BuildContext context, WatchlistItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name.isEmpty ? item.code : item.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.show_chart),
              title: const Text('查看详情'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/detail/${item.code}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('添加到持仓'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/trade?code=${item.code}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('设置提醒'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/reminder?code=${item.code}');
              },
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
