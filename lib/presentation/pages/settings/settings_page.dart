import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 0=跟随系统, 1=浅色, 2=深色
  late int _themeIndex;

  static const _themeOptions = ['跟随系统', '浅色', '深色'];
  static const _themeModes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ThemeModeNotifier.of(context).value;
    _themeIndex = _themeModes.indexOf(current);
    if (_themeIndex < 0) _themeIndex = 0;
  }

  void _setTheme(int index) {
    setState(() => _themeIndex = index);
    ThemeModeNotifier.of(context).value = _themeModes[index];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          _buildSection('通用', [
            _buildTile(Icons.notifications_outlined, '通知提醒', () {}, trailing: const Icon(Icons.chevron_right, size: 18)),
            _buildThemeTile(),
            _buildTile(Icons.language, '语言', () {}, trailing: const Icon(Icons.chevron_right, size: 18)),
          ]),
          _buildSection('数据', [
            _buildTile(Icons.sync, '同步数据', () {}, trailing: const Icon(Icons.chevron_right, size: 18)),
            _buildTile(Icons.delete_outline, '清除缓存', () {}, trailing: const Icon(Icons.chevron_right, size: 18)),
            _buildTile(Icons.backup_outlined, '备份与恢复', () {}, trailing: const Icon(Icons.chevron_right, size: 18)),
          ]),
          _buildSection('其他', [
            _buildTile(Icons.info_outline, '关于', () {}, trailing: const Text('v1.0.0', style: TextStyle(fontSize: 13, color: AppTheme.textMuted))),
            _buildTile(Icons.help_outline, '帮助与反馈', () {}, trailing: const Icon(Icons.chevron_right, size: 18)),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildThemeTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.palette_outlined, color: AppTheme.primary, size: 22),
              const SizedBox(width: 16),
              const Expanded(child: Text('主题模式', style: TextStyle(fontSize: 16))),
              SegmentedButton<int>(
                segments: List.generate(3, (i) => ButtonSegment<int>(
                  value: i,
                  label: Text(_themeOptions[i], style: const TextStyle(fontSize: 12)),
                )),
                selected: {_themeIndex},
                onSelectionChanged: (v) => _setTheme(v.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }

  Widget _buildTile(IconData icon, String label, VoidCallback onTap, {required Widget trailing}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 22),
      title: Text(label),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

/// 全局主题模式通知器（方便任意页面切换）
class ThemeModeNotifier extends InheritedNotifier<ValueNotifier<ThemeMode>> {
  const ThemeModeNotifier({
    super.key,
    required ValueNotifier<ThemeMode> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<ThemeMode> of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ThemeModeNotifier>();
    assert(widget != null, 'No ThemeModeNotifier found in context');
    return widget!.notifier!;
  }
}
