import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/trade/trade_bloc.dart';
import '../../bloc/trade/trade_event.dart';
import '../../bloc/trade/trade_state.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../core/theme/app_theme.dart';

class TradePage extends StatefulWidget {
  final String? fundCode;
  const TradePage({super.key, this.fundCode});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<TradeBloc>();
    bloc.add(TradeLoadRecords(fundCode: widget.fundCode));
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFAB(context),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.bgPrimary,
      elevation: 0,
      title: const Text('交易记录', style: TextStyle(color: AppTheme.textPrimary)),
      iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      bottom: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.primary,
        tabs: const [
          Tab(text: '全部'),
          Tab(text: '买入'),
          Tab(text: '卖出'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return BlocConsumer<TradeBloc, TradeState>(
      listener: (ctx, state) {
        if (state.status == TradeBlocStatus.saved) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('交易记录已保存'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      builder: (ctx, state) {
        if (state.status == TradeBlocStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == TradeBlocStatus.error) {
          return _buildError(state.errorMessage ?? '加载失败');
        }

        final filtered = switch (_tabController.index) {
          1 => state.records.where((r) => r.type == TradeType.buy).toList(),
          2 => state.records.where((r) => r.type == TradeType.sell).toList(),
          _ => state.records,
        };

        if (filtered.isEmpty) {
          return _buildEmpty();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtered.length,
          itemBuilder: (ctx2, i) => _buildRecordCard(ctx2, filtered[i]),
        );
      },
    );
  }

  Widget _buildFAB(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showAddDialog(context),
      backgroundColor: AppTheme.primary,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('新增交易', style: TextStyle(color: Colors.white)),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off,
              size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('加载失败',
              style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  fontSize: 16)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              msg,
              style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context
                .read<TradeBloc>()
                .add(TradeLoadRecords(fundCode: widget.fundCode)),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
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
          Icon(Icons.receipt_long,
              size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('暂无交易记录',
              style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text('点击右下角添加买入/卖出记录',
              style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildRecordCard(BuildContext ctx, TradeRecord record) {
    final typeLabel = switch (record.type) {
      TradeType.buy => '买入',
      TradeType.sell => '卖出',
      TradeType.dividend => '分红',
      TradeType.autoInvest => '定投',
    };
    final typeColor = switch (record.type) {
      TradeType.buy => Colors.green,
      TradeType.sell => Colors.red,
      _ => AppTheme.primary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(typeLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: typeColor,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(record.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppTheme.textSecondary),
                onPressed: () => _confirmDelete(ctx, record),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoChip('代码', record.code),
              const SizedBox(width: 16),
              _infoChip('日期', record.date),
              const SizedBox(width: 16),
              _infoChip('金额', '¥${record.amount.toStringAsFixed(0)}'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _infoChip(
                  '净值',
                  record.netValue > 0
                      ? record.netValue.toStringAsFixed(4)
                      : '-'),
              const SizedBox(width: 16),
              _infoChip(
                  '份额',
                  record.shares.abs() > 0
                      ? record.shares.abs().toStringAsFixed(2)
                      : '-'),
              const SizedBox(width: 16),
              _infoChip('手续费',
                  record.fee > 0 ? '¥${record.fee.toStringAsFixed(2)}' : '-'),
            ],
          ),
          if (record.remark != null && record.remark!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(record.remark!,
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary.withValues(alpha: 0.7))),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary.withValues(alpha: 0.6))),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _confirmDelete(BuildContext ctx, TradeRecord record) {
    showDialog(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title:
            const Text('删除确认', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定删除 "${record.name}" 的交易记录？',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              context.read<TradeBloc>().add(TradeDelete(record.id));
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.bgPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _AddTradeSheet(fundCode: widget.fundCode),
    );
  }
}

// ── 新增交易表单 ───────────────────────────────────────────

class _AddTradeSheet extends StatefulWidget {
  final String? fundCode;
  const _AddTradeSheet({this.fundCode});

  @override
  State<_AddTradeSheet> createState() => _AddTradeSheetState();
}

class _AddTradeSheetState extends State<_AddTradeSheet> {
  final _codeCtrl = TextEditingController(text: '');
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _navCtrl = TextEditingController();
  final _feeCtrl = TextEditingController(text: '0');
  final _remarkCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  TradeType _type = TradeType.buy;
  String _date = DateTime.now().toIso8601String().split('T')[0];

  @override
  void initState() {
    super.initState();
    if (widget.fundCode != null) {
      _codeCtrl.text = widget.fundCode!;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _navCtrl.dispose();
    _feeCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖动条
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('新增交易',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 20),

              // 交易类型
              Row(
                children: [
                  _typeBtn('买入', TradeType.buy, Colors.green),
                  const SizedBox(width: 12),
                  _typeBtn('卖出', TradeType.sell, Colors.red),
                  const SizedBox(width: 12),
                  _typeBtn('定投', TradeType.autoInvest, AppTheme.primary),
                ],
              ),
              const SizedBox(height: 16),

              // 基金代码
              TextFormField(
                controller: _codeCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _inputDeco('基金代码 *', hint: '如 005827'),
                keyboardType: TextInputType.text,
                validator: (v) => v == null || v.isEmpty ? '请输入基金代码' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // 基金名称
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _inputDeco('基金名称 *', hint: '如 易方达蓝筹精选混合'),
                validator: (v) => v == null || v.isEmpty ? '请输入基金名称' : null,
              ),
              const SizedBox(height: 12),

              // 金额 + 净值
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _inputDeco('金额(元) *', hint: '1000'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v == null || v.isEmpty ? '必填' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _navCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _inputDeco('净值', hint: '2.1540'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 日期
              _dateField(),
              const SizedBox(height: 12),

              // 手续费
              TextFormField(
                controller: _feeCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _inputDeco('手续费(元)', hint: '0'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),

              // 备注
              TextFormField(
                controller: _remarkCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _inputDeco('备注', hint: '可选'),
              ),
              const SizedBox(height: 24),

              // 提交
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _type == TradeType.sell ? Colors.red : AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('保存',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBtn(String label, TradeType type, Color color) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? color : AppTheme.borderColor,
                width: selected ? 2 : 1),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: selected ? color : AppTheme.textSecondary,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
          ),
        ),
      ),
    );
  }

  Widget _dateField() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (_, child) => Theme(
            data: Theme.of(context).copyWith(
                colorScheme:
                    const ColorScheme.light(primary: AppTheme.primary)),
            child: child!,
          ),
        );
        if (picked != null) {
          setState(() => _date = picked.toIso8601String().split('T')[0]);
        }
      },
      child: InputDecorator(
        decoration: _inputDeco('交易日期'),
        child: Row(
          children: [
            Text(_date,
                style:
                    const TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
            const Spacer(),
            const Icon(Icons.calendar_today,
                size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final netValue = double.tryParse(_navCtrl.text) ?? 0;
    final fee = double.tryParse(_feeCtrl.text) ?? 0;

    // 计算份额
    double shares = 0;
    if (netValue > 0 && amount > 0) {
      shares = _type == TradeType.buy
          ? amount / netValue
          : -amount / netValue; // 卖出时 shares 为负表示减少
    }

    final record = TradeRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      code: _codeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      type: _type,
      date: _date,
      amount: amount,
      netValue: netValue,
      shares: shares,
      fee: fee,
      remark:
          _remarkCtrl.text.trim().isNotEmpty ? _remarkCtrl.text.trim() : null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      status: TradeStatus.completed,
    );

    context.read<TradeBloc>().add(TradeAdd(record));
    Navigator.pop(context);
  }

  InputDecoration _inputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle:
          TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.8)),
      hintStyle:
          TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4)),
      filled: true,
      fillColor: AppTheme.bgCard,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}
