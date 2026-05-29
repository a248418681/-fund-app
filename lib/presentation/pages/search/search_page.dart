import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../bloc/home/home_bloc.dart';
import '../../bloc/home/home_event.dart';
import '../../bloc/holdings/holdings_bloc.dart';
import '../../bloc/holdings/holdings_event.dart';
import '../../bloc/search/search_bloc.dart';
import '../../bloc/search/search_event.dart';
import '../../bloc/search/search_state.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final SearchBloc _searchBloc;
  late final HoldingsBloc _holdingsBloc;
  late final HomeBloc _homeBloc;

  @override
  void initState() {
    super.initState();
    _searchBloc = getIt<SearchBloc>();
    // 使用单例 HoldingsBloc/HomeBloc，和 MainPage/主页 共享同一个实例
    _holdingsBloc = getIt<HoldingsBloc>();
    _homeBloc = getIt<HomeBloc>();
    _searchBloc.add(const SearchQueryChanged(''));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    // SearchBloc/HoldingsBloc/HomeBloc 都是全局单例，不在这里关闭
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SearchBloc>.value(value: _searchBloc),
        BlocProvider<HoldingsBloc>.value(value: _holdingsBloc),
        BlocProvider<HomeBloc>.value(value: _homeBloc),
      ],
      child: Scaffold(
        backgroundColor: AppTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AppTheme.bgPrimary,
          elevation: 0,
          titleSpacing: 0,
          title: _buildSearchBar(),
        ),
        body: BlocBuilder<SearchBloc, SearchState>(
          builder: (ctx, state) {
            return Column(
              children: [
                if (state.status == SearchStatus.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(
                  child: state.query.isEmpty
                      ? _buildHotFunds(ctx, state)
                      : _buildResults(ctx, state),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (ctx, state) {
        return Container(
          height: 40,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '搜索基金名称或代码',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
              suffixIcon: state.query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                      onPressed: () {
                        _controller.clear();
                        ctx.read<SearchBloc>().add(const SearchCleared());
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => ctx.read<SearchBloc>().add(SearchQueryChanged(v)),
            textInputAction: TextInputAction.search,
          ),
        );
      },
    );
  }

  Widget _buildHotFunds(BuildContext ctx, SearchState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('🔥 热门基金', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        if (state.hotFunds.isEmpty)
          const Center(
            child: Padding(padding: EdgeInsets.all(32),
              child: Text('正在加载...', style: TextStyle(color: AppTheme.textSecondary)),
            ),
          )
        else
          ...state.hotFunds.map((f) => _FundTile(fund: f, onTap: () => _showFundActions(ctx, f))),
        const SizedBox(height: 24),
        _buildTip(),
      ],
    );
  }

  Widget _buildResults(BuildContext ctx, SearchState state) {
    if (state.status == SearchStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('搜索失败', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6))),
            TextButton(
              onPressed: () => ctx.read<SearchBloc>().add(SearchQueryChanged(state.query)),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (state.results.isEmpty && state.status == SearchStatus.loaded) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('未找到 "${state.query}"', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6))),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.results.length,
      itemBuilder: (ctx2, i) => _FundTile(
        fund: state.results[i],
        onTap: () => _showFundActions(ctx2, state.results[i]),
      ),
    );
  }

  void _showFundActions(BuildContext ctx, FundInfo fund) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.bgPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => _FundActionsSheet(
        fund: fund,
        onAddHolding: () => _addToHolding(fund),
        onAddWatchlist: () => _addToWatchlist(ctx, fund),
      ),
    );
  }

  void _addToHolding(FundInfo fund) {
    Navigator.pop(context);
    _showAddHoldingDialog(fund);
  }

  void _addToWatchlist(BuildContext ctx, FundInfo fund) {
    // pop 前先获取 ScaffoldMessenger，避免 ctx 在 pop 后被 dispose
    final messenger = ScaffoldMessenger.of(ctx);
    Navigator.pop(context);
    _homeBloc.add(HomeAddWatchlist(fund.code, fund.name));
    messenger.showSnackBar(
      SnackBar(
        content: Text('已添加 "${fund.name}" 到自选'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showAddHoldingDialog(FundInfo fund) async {
    // 预取当前净值，用实际估值替代默认 1.0
    double defaultNav = 1.0;
    try {
      final repo = getIt<FundRepository>();
      final data = await repo.fetchFundAccurateData(fund.code);
      if (data.nav > 0) {
        defaultNav = data.nav;
      } else if (data.currentValue > 0 && data.currentValue < 100) {
        defaultNav = data.currentValue;
      }
    } catch (_) {
      // 获取失败使用默认 1.0
    }

    if (!mounted) return;

    final amountCtrl = TextEditingController(text: '1000');
    final navCtrl = TextEditingController(text: defaultNav.toStringAsFixed(4));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(sheet).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.textSecondary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('添加 ${fund.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            Text(fund.code, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary.withValues(alpha: 0.7))),
            const SizedBox(height: 20),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: '买入金额(元)',
                hintText: '1000',
                labelStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                filled: true,
                fillColor: AppTheme.bgCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: navCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: '买入净值',
                hintText: defaultNav > 1.0 ? '已获取最新净值' : '请输入买入净值',
                labelStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                filled: true,
                fillColor: AppTheme.bgCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (amount <= 0) return;
                  final nav = double.tryParse(navCtrl.text);
                  final effectiveNav = nav != null && nav > 0 ? nav : 1.0;
                  final shares = amount / effectiveNav;

                  final holding = HoldingRecord(
                    code: fund.code,
                    name: fund.name,
                    shareClass: 'A',
                    amount: amount,
                    buyNetValue: effectiveNav,
                    shares: shares,
                    buyDate: DateTime.now().toIso8601String().split('T')[0],
                    holdingDays: 0,
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                  );

                  _holdingsBloc.add(HoldingsAdd(holding));
                  Navigator.pop(sheet);  // 关闭 bottom sheet
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已添加 "${fund.name}" 到持仓（¥${amount.toStringAsFixed(0)}）'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('确认添加', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text('点击基金可查看详情或添加到持仓', style: TextStyle(fontSize: 12, color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}

// ── 基金行组件 ───────────────────────────────────────────

class _FundTile extends StatelessWidget {
  final dynamic fund;
  final VoidCallback onTap;

  const _FundTile({required this.fund, required this.onTap});

  @override
  Widget build(BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(
            child: Text(
              fund.type.isNotEmpty ? fund.type[0] : '?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
          ),
        ),
        title: Text(fund.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
        subtitle: Text(fund.code,
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.7))),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 22),
      ),
    );
  }
}

// ── 操作面板 ───────────────────────────────────────────

class _FundActionsSheet extends StatelessWidget {
  final FundInfo fund;
  final VoidCallback onAddHolding;
  final VoidCallback onAddWatchlist;

  const _FundActionsSheet({
    required this.fund,
    required this.onAddHolding,
    required this.onAddWatchlist,
  });

  @override
  Widget build(BuildContext ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 基金信息
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: Text(fund.name.isNotEmpty ? fund.name[0] : '?',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fund.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        Text('${fund.code} · ${fund.type}', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () { Navigator.pop(ctx); ctx.push('/detail/${fund.code}'); },
                    child: const Text('详情'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.pie_chart_outline,
                    label: '加入持仓',
                    color: AppTheme.primary,
                    onTap: onAddHolding,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.star_outline,
                    label: '加入自选',
                    color: Colors.orange,
                    onTap: onAddWatchlist,
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

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext ctx) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
