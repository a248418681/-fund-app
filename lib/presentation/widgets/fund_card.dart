import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// 可复用的基金卡片
///
/// 视觉升级要点：
/// - 左侧涨跌色竖条，一眼分辨涨跌
/// - 涨跌幅做成带浅色背景的 pill 标签（不再是裸文字）
/// - 柔和阴影替代硬边框，更有层次
/// - 数据源（净值/估值）精致 chip
///
/// 设计为纯展示组件，数据通过参数传入，便于自选/持仓/行情多页复用。
class FundCard extends StatelessWidget {
  const FundCard({
    super.key,
    required this.name,
    required this.code,
    required this.value,
    required this.changePercent,
    this.subtitle,
    this.sourceLabel,
    this.isNavSource = false,
    this.onTap,
    this.onLongPress,
  });

  /// 基金名称（为空时回退显示代码）
  final String name;

  /// 基金代码
  final String code;

  /// 主数值（估算净值 / 净值），已格式化的字符串
  final String? value;

  /// 涨跌幅百分比数值（用于颜色与符号），单位 %
  final double? changePercent;

  /// 副标题（如估值时间），可空
  final String? subtitle;

  /// 数据源标签文字（如「净值」「估值」），为空则不显示
  final String? sourceLabel;

  /// 数据源是否为净值（影响 chip 配色：净值蓝 / 估值橙）
  final bool isNavSource;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final changeColor = AppTheme.changeColor(changePercent);
    final changeBg = AppTheme.changeBgColor(changePercent);
    final pctText = AppTheme.formatPercent(changePercent);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: IntrinsicHeight(
            child: Row(
              children: [
                // 左侧涨跌色竖条
                Container(width: 4, color: changeColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                    child: Row(
                      children: [
                        // 名称 + 代码 + 数据源 chip
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name.isEmpty ? code : name,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (sourceLabel != null) ...[
                                    const SizedBox(width: 8),
                                    _SourceChip(
                                        label: sourceLabel!,
                                        isNav: isNavSource),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Text(
                                    code,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  if (subtitle != null &&
                                      subtitle!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      subtitle!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 右侧：净值 + 涨跌 pill
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              value ?? '--',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: changeColor,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: changeBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pctText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: changeColor,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 数据源 chip：净值（蓝）/ 估值（橙）
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label, required this.isNav});

  final String label;
  final bool isNav;

  @override
  Widget build(BuildContext context) {
    final color = isNav ? AppTheme.primary : const Color(0xFFFF9500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
