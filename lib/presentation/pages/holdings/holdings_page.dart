import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../bloc/holdings/holdings_bloc.dart';
import '../../bloc/holdings/holdings_event.dart';
import '../../bloc/holdings/holdings_state.dart';

class HoldingsPage extends StatefulWidget {
  const HoldingsPage({super.key});

  @override
  State<HoldingsPage> createState() => _HoldingsPageState();
}

class _HoldingsPageState extends State<HoldingsPage> with WidgetsBindingObserver {
  // 主控滚动器（表头）
  final ScrollController _headerScrollCtrl = ScrollController();
  // 数据行的滚动器列表
  final List<ScrollController> _rowScrollCtrls = [];
  bool _syncing = false; // 防止循环触发

  late final HoldingsBloc _bloc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = context.read<HoldingsBloc>();
    if (_bloc.state.status == HoldingsStatus.initial) {
      _bloc.add(HoldingsLoad());
    } else if (_bloc.state.status == HoldingsStatus.loaded) {
      // 已有数据时，进入页面自动静默刷新
      _bloc.add(HoldingsSilentRefresh());
    }
    // 启动交易时间自动刷新
    _bloc.startAutoRefresh();
    // 监听表头滚动，同步到所有数据行
    _headerScrollCtrl.addListener(_syncToRows);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App 回到前台：静默刷新 + 重启自动刷新
      _bloc.add(HoldingsSilentRefresh());
      _bloc.startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      // App 到后台：停止自动刷新（省电）
      _bloc.stopAutoRefresh();
    }
  }

  void _syncToRows() {
    if (_syncing) return;
    _syncing = true;
    final offset = _headerScrollCtrl.offset;
    for (final ctrl in _rowScrollCtrls) {
      if (ctrl.hasClients && ctrl.offset != offset) {
        ctrl.jumpTo(offset);
      }
    }
    _syncing = false;
  }

  void _ensureRowControllers(int count) {
    while (_rowScrollCtrls.length < count) {
      final ctrl = ScrollController();
      ctrl.addListener(() => _syncFromRow(ctrl));
      _rowScrollCtrls.add(ctrl);
    }
    while (_rowScrollCtrls.length > count) {
      _rowScrollCtrls.removeLast().dispose();
    }
  }

  void _syncFromRow(ScrollController source) {
    if (_syncing || !source.hasClients) return;
    _syncing = true;
    final offset = source.offset;
    if (_headerScrollCtrl.hasClients && _headerScrollCtrl.offset != offset) {
      _headerScrollCtrl.jumpTo(offset);
    }
    for (final ctrl in _rowScrollCtrls) {
      if (ctrl != source && ctrl.hasClients && ctrl.offset != offset) {
        ctrl.jumpTo(offset);
      }
    }
    _syncing = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.stopAutoRefresh();
    _headerScrollCtrl.removeListener(_syncToRows);
    _headerScrollCtrl.dispose();
    for (final ctrl in _rowScrollCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  static const double _nameW = 90.0;
  static const double _colW = 72.0;
  static const double _padH = 12.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('我的持仓', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A),
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primary),
            tooltip: '截图导入',
            onPressed: () => context.push('/import'),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary),
            tooltip: '添加持仓',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: BlocBuilder<HoldingsBloc, HoldingsState>(
        builder: (context, state) {
          if (state.status == HoldingsStatus.loading) {
            return _buildSkeleton();
          }
          if (state.status == HoldingsStatus.error) {
            return _buildError(state.errorMessage ?? '加载失败');
          }
          _ensureRowControllers(state.holdings.length);
          return Column(
            children: [
              _buildSummaryBar(state),
              if (state.holdings.isNotEmpty) ...[
                _buildTableHeader(state),
                Expanded(child: _buildTableBody(state)),
              ] else
                Expanded(child: _buildEmpty()),
              _buildBottomLinks(state),
            ],
          );
        },
      ),
    );
  }

  // ── 顶部汇总 ───────────────────────────────────────────────
  Widget _buildSummaryBar(HoldingsState state) {
    final s = state.summary;
    final todayUp = s.todayProfit > 0;
    final todayDown = s.todayProfit < 0;
    
    // 从第一个持仓获取更新时间
    final firstHolding = state.holdings.isNotEmpty ? state.holdings.first : null;
    final changeUpdateTime = firstHolding?.changeUpdateTime ?? '';
    
    // 时间感知标签
    final estLabel = _estimateColumnLabel(state);
    final navLabel = _navColumnLabel(state);
    final timeContext = '估算=$estLabel · 净值=$navLabel';

    // 刷新时间提示
    final refreshHint = _formatRefreshTime(state.lastRefreshTime);
    
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 14,
        bottom: 14 + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _sumItem('账户资产', AppTheme.formatMoney(s.totalValue)),
              Container(width: 1, height: 32,
                color: const Color(0xFFEEEEEE),
                margin: const EdgeInsets.symmetric(horizontal: 20)),
              _sumItem(
                '今日收益',
                '${s.todayProfit > 0 ? '+' : ''}${s.todayProfit.toStringAsFixed(2)}',
                color: todayUp ? AppTheme.upColor
                    : (todayDown ? AppTheme.downColor : const Color(0xFF1A1A1A)),
              ),
            ],
          ),
          // 显示数据类型、更新时间和刷新时间
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                timeContext,
                if (changeUpdateTime.isNotEmpty) changeUpdateTime,
                if (refreshHint != null) refreshHint,
              ].join(' · '),
              style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化刷新时间提示
  String? _formatRefreshTime(DateTime? time) {
    if (time == null) return null;
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 10) return '刚刚更新';
    if (diff.inMinutes < 1) return '${diff.inSeconds}秒前更新';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前更新';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}更新';
  }

  Widget _sumItem(String label, String val, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.bold,
          color: color ?? const Color(0xFF1A1A1A),
        )),
      ],
    );
  }

  // ── 表头 ───────────────────────────────────────────────────
  /// 时间感知的估算列标签
  String _estimateColumnLabel(HoldingsState state) {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    final weekday = now.weekday;
    final isWeekend = weekday == 6 || weekday == 7;
    if (isWeekend) return '上日估算';
    if (h < 9 || (h == 9 && m < 30)) return '昨日估算';
    return '今日估算';
  }

  /// 时间感知的净值列标签
  String _navColumnLabel(HoldingsState state) {
    // 净值始终显示上一发布日数据，只有 navUpdated=true 时才是今日
    if (state.holdings.isNotEmpty && state.holdings.first.navUpdated) return '今日净值';
    return '昨日净值';
  }

  Widget _buildTableHeader(HoldingsState state) {
    final estLabel = _estimateColumnLabel(state);
    final navLabel = _navColumnLabel(state);
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 8),
      child: Row(
        children: [
          _sortHeader('基金名称', _nameW, HoldingsSortField.name, state),
          Expanded(
            child: SingleChildScrollView(
              controller: _headerScrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  _sortHeader('持仓市值', _colW, HoldingsSortField.marketValue, state),
                  _sortHeader(estLabel, _colW, HoldingsSortField.estimateChange, state),
                  _sortHeader(navLabel, _colW, HoldingsSortField.netValueChange, state),
                  _sortHeader('今日收益', _colW, HoldingsSortField.todayProfit, state),
                  _sortHeader('持有收益', _colW, HoldingsSortField.totalProfit, state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortHeader(String label, double width, HoldingsSortField field, HoldingsState state) {
    final isActive = state.sortField == field;
    return GestureDetector(
      onTap: () => _bloc.add(HoldingsChangeSort(field)),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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

  // ── 表格主体 ────────────────────────────────────────────────
  Widget _buildTableBody(HoldingsState state) {
    return RefreshIndicator(
      color: AppTheme.primary,
      displacement: 40,
      onRefresh: () async {
        _bloc.add(HoldingsRefresh());
        // 等待 isRefreshing 变回 false
        await _bloc.stream.firstWhere(
          (s) => !s.isRefreshing,
          orElse: () => state,
        );
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        itemCount: state.sortedHoldings.length,
        itemBuilder: (ctx, i) => _buildRow(state.sortedHoldings[i], i),
      ),
    );
  }

  Widget _buildRow(HoldingWithProfit h, int idx) {
    final dayPct = double.tryParse(h.todayChange) ?? 0;
    final isUp = dayPct > 0;
    final isFlat = dayPct == 0;
    final pctColor = isFlat
        ? const Color(0xFF999999)
        : (isUp ? AppTheme.upColor : AppTheme.downColor);
    final pctStr = isFlat
        ? '${dayPct.toStringAsFixed(2)}%'
        : '${isUp ? '+' : ''}${dayPct.toStringAsFixed(2)}%';

    final profitVal = double.tryParse(h.profitRate) ?? 0;
    final estChange = h.estimateChange ?? 0;
    final hasEst = h.estimateTime?.isNotEmpty == true;
    final estUp = estChange > 0;
    final estFlat = estChange.abs() <= 0.001 && hasEst;
    final estCol = estFlat
        ? const Color(0xFF999999)
        : (estUp ? AppTheme.upColor : AppTheme.downColor);

    return GestureDetector(
      onTap: () => context.push('/detail/${h.code}'),
      onLongPress: () => _showActionMenu(h),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: _padH, vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // ── 名称（固定左）────────────────────────────
            SizedBox(
              width: _nameW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.name.isEmpty ? h.code : h.name,
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(h.code,
                        style: const TextStyle(fontSize: 10, color: Color(0xFFBBBBBB))),
                      // API获取失败标记
                      if (h.hasError) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text('获取失败',
                            style: TextStyle(fontSize: 8, color: Color(0xFFE65100), fontWeight: FontWeight.w500)),
                        ),
                      ],
                      // 净值已更新标签
                      if (h.navUpdated) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text('已更新',
                            style: TextStyle(fontSize: 8, color: Color(0xFF4CAF50), fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // ── 数据列（可滚动）──────────────────────────
            Expanded(
              child: SingleChildScrollView(
                controller: _rowScrollCtrls[idx],
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  children: [
                    _dCell(
                        h.marketValue > 0
                            ? h.marketValue.toStringAsFixed(2)
                            : '--',
                        const Color(0xFF1A1A1A), _colW),
                    _dCell(hasEst ? '${estUp ? '+' : ''}${estChange.toStringAsFixed(2)}%' : '--', estCol, _colW),
                    _dCell(pctStr, pctColor, _colW),
                    _dCell(
                        '${h.todayProfit > 0 && h.todayProfit != 0 ? '+' : ''}${h.todayProfit.toStringAsFixed(2)}',
                        AppTheme.changeColor(h.todayProfit), _colW),
                    _dCell(
                        '${profitVal > 0 && profitVal != 0 ? '+' : ''}${h.profit.toStringAsFixed(2)}',
                        AppTheme.changeColor(profitVal), _colW),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dCell(String t, Color c, double w) {
    return SizedBox(
      width: w,
      child: Text(t, textAlign: TextAlign.right,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
        overflow: TextOverflow.ellipsis),
    );
  }

  // ── 空状态 ─────────────────────────────────────────────────
  Widget _buildError(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 12),
          const Text('加载失败',
              style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              msg,
              style: const TextStyle(fontSize: 11, color: Color(0xFFBBBBBB)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _bloc.add(HoldingsLoad()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text('重试',
                  style: TextStyle(fontSize: 13, color: Colors.white,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 12),
          const Text('暂无持仓',
              style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => context.push('/search'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text('添加持仓',
                  style: TextStyle(fontSize: 13, color: Colors.white,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 骨架屏 ─────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _skItem(),
              Container(width: 1, height: 32,
                color: const Color(0xFFEEEEEE),
                margin: const EdgeInsets.symmetric(horizontal: 20)),
              _skItem(),
            ],
          ),
        ),
        _buildTableHeaderSkeleton(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            itemCount: 4,
            itemBuilder: (_, __) => Container(
              margin: const EdgeInsets.symmetric(horizontal: _padH, vertical: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: _nameW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skBox(70, 12),
                        const SizedBox(height: 4),
                        _skBox(44, 10),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: List.generate(
                          5,
                          (_) => Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: _skBox(52, 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _skItem() => Column(
    children: [
      _skBox(44, 11),
      const SizedBox(height: 6),
      _skBox(72, 17),
    ],
  );

  Widget _skBox(double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F0F0),
      borderRadius: BorderRadius.circular(3),
    ),
  );

  // ── 骨架屏占位表头 ─────────────────────────────────────────
  Widget _buildTableHeaderSkeleton() {
    const headerStyle = TextStyle(fontSize: 12, color: Color(0xFF999999));
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _nameW,
            child: const Text('基金名称', style: headerStyle),
          ),
          const Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: ClampingScrollPhysics(),
              child: Row(
                children: [
                  SizedBox(width: _colW, child: Text('持仓市值', style: headerStyle, textAlign: TextAlign.right)),
                  SizedBox(width: _colW, child: Text('今日估算', style: headerStyle, textAlign: TextAlign.right)),
                  SizedBox(width: _colW, child: Text('昨日净值', style: headerStyle, textAlign: TextAlign.right)),
                  SizedBox(width: _colW, child: Text('今日收益', style: headerStyle, textAlign: TextAlign.right)),
                  SizedBox(width: _colW, child: Text('持有收益', style: headerStyle, textAlign: TextAlign.right)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 底部链接 ───────────────────────────────────────────────
  Widget _buildBottomLinks(HoldingsState state) {
    final isInTrading = HoldingsBloc.isInTradingTime();
    return Container(
      color: const Color(0xFFF5F6FA),
      padding: EdgeInsets.only(
        top: 16,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 自动刷新状态指示
          GestureDetector(
            onTap: state.isRefreshing
                ? null
                : () => _bloc.add(HoldingsRefresh()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isRefreshing)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF999999)),
                    )
                  else if (isInTrading)
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: Color(0xFF4CAF50),
                          blurRadius: 4, spreadRadius: 1,
                        )],
                      ),
                    )
                  else
                    const Icon(Icons.access_time, size: 12, color: Color(0xFFBBBBBB)),
                  const SizedBox(width: 4),
                  Text(
                    state.isRefreshing
                        ? '刷新中'
                        : (isInTrading ? '自动刷新中' : '刷新数据'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isInTrading && !state.isRefreshing
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () => context.push('/import'),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, size: 14, color: Color(0xFF999999)),
                  SizedBox(width: 4),
                  Text('截图导入', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () => context.push('/search'),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('添加持仓',
                style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
            ),
          ),
        ],
      ),
    );
  }

  // ── 长按菜单 ───────────────────────────────────────────────
  void _showActionMenu(HoldingWithProfit h) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(h.name.isEmpty ? h.code : h.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A))),
            Text(h.code,
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
            const SizedBox(height: 16),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
              title: const Text('修改持仓'),
              onTap: () {
                Navigator.pop(ctx);
                // 暂无编辑页，去搜索页重新添加
                context.push('/search');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEE0A24)),
              title: const Text('删除持仓',
                  style: TextStyle(color: Color(0xFFEE0A24))),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(h);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(HoldingWithProfit h) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除 ${h.name.isEmpty ? h.code : h.name} 的持仓？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _bloc.add(HoldingsDelete(h.code));
            },
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFEE0A24))),
          ),
        ],
      ),
    );
  }
}
