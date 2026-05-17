import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:paddle_ocr_flutter/paddle_ocr_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../../core/di/injection.dart';
import '../../../utils/ocr_service.dart';
import '../../bloc/holdings/holdings_bloc.dart';
import '../../bloc/holdings/holdings_event.dart';

/// 导入操作类型
enum ImportOperationType {
  sync,   // 同步持仓
  add,    // 加仓
  reduce, // 减仓
  convert, // 转换
}

/// 截图导入持仓页面
/// 4个步骤：选择图片 → 识别中 → 预览确认 → 导入中
/// 分段式匹配引擎的段结构体
/// OCR文本块的坐标信息
class _OcrBlock {
  final String text;
  final double avgY;  // 代表Y坐标
  final int minX;     // 最左X坐标
  final double centerX; // 中心X坐标
  _OcrBlock({required this.text, required this.avgY, required this.minX, required this.centerX});
}

class _FundNameSegments {
  final String company;  // 基金公司名（2-4字）
  final String? topic;    // 板块/主题特征词
  final String? typeTag; // 类型标签（混合型/债券型/货币型...）
  final String? suffix;  // 分类后缀（A/B/C/D...）

  _FundNameSegments({
    required this.company,
    this.topic,
    this.typeTag,
    this.suffix,
  });

  bool get isEmpty => company.isEmpty && topic == null;
}

class ScreenshotImportPage extends StatefulWidget {
  const ScreenshotImportPage({super.key});

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  _ImportStep _step = _ImportStep.upload;
  String? _imagePath;
  double _ocrProgress = 0;
  String _ocrStatus = '';
  String _rawOcrText = ''; // 调试用：原始OCR文本
  List<_EnhancedHoldingItem> _holdings = [];
  bool _selectAll = true;
  final _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSecondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('截图导入持仓'),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _ImportStep.upload:
        return _buildUploadStep();
      case _ImportStep.recognizing:
        return _buildRecognizingStep();
      case _ImportStep.preview:
        return _buildPreviewStep();
      case _ImportStep.importing:
        return _buildImportingStep();
    }
  }

  // ── 步骤1：选择图片 ────────────────────────────────────────
  Widget _buildUploadStep() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 64, color: AppTheme.textMuted),
                const SizedBox(height: 16),
                const Text('选择持仓截图',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                Text('支持支付宝、天天基金等平台截图',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _UploadButton(
                icon: Icons.camera_alt_outlined, label: '拍照',
                onTap: () => _pickImage(ImageSource.camera),
              )),
              const SizedBox(width: 16),
              Expanded(child: _UploadButton(
                icon: Icons.photo_outlined, label: '相册',
                onTap: () => _pickImage(ImageSource.gallery),
              )),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source, maxWidth: 4096, maxHeight: 16384, imageQuality: 95,
      );
      if (image == null) return;
      setState(() { _imagePath = image.path; _step = _ImportStep.recognizing; });
      await _startOcr(image.path);
    } catch (e) {
      _showError('图片选择失败: $e');
      setState(() => _step = _ImportStep.upload);
    }
  }

  // ── 步骤2：识别中 ────────────────────────────────────────
  Widget _buildRecognizingStep() {
    return Column(
      children: [
        Expanded(
          child: _imagePath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(_imagePath!), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 64)),
                )
              : const SizedBox(),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: _ocrProgress,
                backgroundColor: AppTheme.borderColor,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
              ),
              const SizedBox(height: 12),
              Text(_ocrStatus.isEmpty ? '正在识别...' : _ocrStatus,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _startOcr(String imagePath) async {
    try {
      setState(() { _ocrProgress = 0.1; _ocrStatus = '验证图片...'; });

      // 验证文件
      final file = File(imagePath);
      if (!await file.exists()) {
        if (mounted) { _showError('图片文件不存在'); setState(() => _step = _ImportStep.upload); }
        return;
      }

      if (!mounted) return;
      setState(() { _ocrProgress = 0.2; _ocrStatus = '初始化OCR引擎...'; });

      // 根据平台选择 OCR 引擎
      // Android: PaddleOCR（MLKit 在部分设备闪退）
      // iOS: MLKit（稳定，PaddleOCR 暂不支持 iOS）
      String text;
      if (Platform.isAndroid) {
        text = await _recognizeWithPaddleOcr(imagePath);
      } else if (Platform.isIOS) {
        text = await _recognizeWithMlKit(imagePath);
      } else {
        if (mounted) { _showError('当前平台不支持OCR'); setState(() => _step = _ImportStep.upload); }
        return;
      }

      if (!mounted) return;
      debugPrint('[OCR] 识别文本长度: ${text.length}');
      // ★ 调试：写入文件保存完整原始文本
      try {
        final dir = Directory(r'/data/data/com.example.fund_app/files');
        if (!await dir.exists()) {
          // Android 10+ 外部存储 fallback
          final extDir = Directory(r'/sdcard');
          if (await extDir.exists()) {
            final file = File(r'/sdcard/fund_ocr_raw.txt');
            await file.writeAsString(text);
            debugPrint('[OCR] 完整文本已保存到 /sdcard/fund_ocr_raw.txt');
          }
        } else {
          final file = File('${dir.path}/fund_ocr_raw.txt');
          await file.writeAsString(text);
          debugPrint('[OCR] 完整文本已保存到 ${dir.path}/fund_ocr_raw.txt');
        }
      } catch (e) {
        debugPrint('[OCR] 保存失败: $e');
      }
      debugPrint('[OCR] 前200字: ${text.length > 200 ? text.substring(0, 200) : text}');
      _rawOcrText = text; // 调试用

      if (text.trim().isEmpty) {
        if (mounted) { _showError('未识别到文字，请确保截图清晰'); setState(() => _step = _ImportStep.upload); }
        return;
      }

      if (!mounted) return;
      setState(() { _ocrProgress = 0.7; _ocrStatus = '解析持仓信息...'; });

      final parsed = OcrService.parseHoldingText(text);
      debugPrint('[OCR] 解析结果: ${parsed.length} 条');

      // ★ 即使解析失败也跳转到preview，方便看调试面板
      if (parsed.isEmpty) {
        if (mounted) {
          setState(() {
            _holdings = [];
            _step = _ImportStep.preview; // 不直接退回upload
          });
          // 显示警告但不阻止用户看调试面板
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('未识别到持仓信息，请查看调试面板'),
                behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }

      final existingCodes = await _getExistingHoldingCodes();
      final enhanced = await _enhanceHoldings(parsed, existingCodes);

      if (!mounted) return;
      setState(() {
        _holdings = enhanced;
        _step = _ImportStep.preview;
        _selectAll = true;
      });
    } catch (e, stack) {
      debugPrint('[OCR] 异常: $e\n$stack');
      if (mounted) { _showError('识别失败: $e'); setState(() => _step = _ImportStep.upload); }
    }
  }

  /// Android: PaddleOCR 本地离线识别
  Future<String> _recognizeWithPaddleOcr(String imagePath) async {
    final ocr = PaddleOcrFlutter();
    try {
      await ocr.init();
      if (!mounted) setState(() { _ocrProgress = 0.4; _ocrStatus = '识别文字中...'; });
      final results = await ocr.recognize(imagePath);
      // ★ Step1: 保存原始块数据用于X坐标分析
      try {
        final blockData = results.map((r) {
          if (r.points.isEmpty) return {'text': r.text, 'avgY': 0, 'minX': 0, 'maxX': 0, 'minY': 0, 'maxY': 0, 'w': 0, 'h': 0, 'centerX': 0};
          final xs = r.points.map((p) => p.x).toList();
          final ys = r.points.map((p) => p.y).toList();
          final minX = xs.reduce((a, b) => a < b ? a : b);
          final maxX = xs.reduce((a, b) => a > b ? a : b);
          final minY = ys.reduce((a, b) => a < b ? a : b);
          final maxY = ys.reduce((a, b) => a > b ? a : b);
          return {'text': r.text, 'avgY': ys.reduce((a, b) => a + b) / ys.length,
            'minX': minX, 'maxX': maxX, 'minY': minY, 'maxY': maxY,
            'w': maxX - minX, 'h': maxY - minY,
            'centerX': (minX + maxX) / 2};
        }).toList();
        await File('/data/data/com.example.fund_app/files/fund_ocr_blocks.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(blockData));
        debugPrint('[OCR-DEBUG] 已保存 ${blockData.length} 个原始块到 files/fund_ocr_blocks.json');
      } catch(e) { debugPrint('[OCR-DEBUG] 保存块数据失败: $e'); }
      // ★ 暂时回退到原来的简单合并，测试识别率
      final rawText = results.map((r) => r.text).join('\n');
      debugPrint('[OCR] 原始合并行数: ${rawText.split('\n').length}');
      debugPrint('[OCR] 原始合并前300字: ${rawText.substring(0, rawText.length > 300 ? 300 : rawText.length)}');
      // 两种合并方式都输出，方便对比
      final smartMerged = _smartMergeOcrLines(rawText);
      debugPrint('[OCR] smartMerge后行数: ${smartMerged.split('\n').length}');
      final yMerged = _mergeOcrByYCoordinate(results);
      debugPrint('[OCR] Y坐标合并后行数: ${yMerged.split('\n').length}');
      // ★ 切换到Y坐标合并（按视觉行合并，解决基金名截断和收益率%粘连问题）
      return yMerged;
    } finally {
      await ocr.dispose();
    }
  }

  /// 按Y坐标合并OCR结果为逻辑行
  /// PaddleOCR会把一行文字拆成多个块，用bounding box的Y坐标
  /// 判断哪些块属于同一行，再按X坐标排序拼接
  /// 列感知 OCR 文本合并（Column-Aware Merge）
  /// 思路：先分析 X 坐标分布找列分界线，分列后各列内按 Y 合并，
  /// 最后跨列按 Y 对齐拼接为单行文本（保持 V8 解析器输入格式不变）
  /// 相比纯 Y-first 合并：防止左列基金名/后缀块被错误混入右列金额列
  static String _mergeOcrByYCoordinate(List<OcrResult> results) {
    if (results.isEmpty) return '';

    // 提取所有块（含 centerX）
    final blocks = <_OcrBlock>[];
    for (final r in results) {
      if (r.text.trim().isEmpty) continue;
      if (r.points.isEmpty) continue;
      final ys = r.points.map((p) => p.y.toDouble()).toList();
      final xs = r.points.map((p) => p.x.toDouble()).toList();
      final avgY = ys.reduce((a, b) => a + b) / ys.length;
      final minX = xs.reduce((a, b) => a < b ? a : b).toInt();
      final maxX = xs.reduce((a, b) => a > b ? a : b).toInt();
      final centerX = (minX + maxX) / 2.0;
      blocks.add(_OcrBlock(
        text: r.text.trim(),
        avgY: avgY,
        minX: minX,
        centerX: centerX,
      ));
    }

    if (blocks.isEmpty) return '';

    // ── Step 1: 估算 Y 合并阈值（相邻 Y 差中位数 × 0.7）
    blocks.sort((a, b) => a.avgY.compareTo(b.avgY));
    final yDiffs = <double>[];
    for (int i = 1; i < blocks.length; i++) {
      yDiffs.add((blocks[i].avgY - blocks[i - 1].avgY).abs());
    }
    yDiffs.sort();
    final yThreshold = yDiffs.isNotEmpty
        ? (yDiffs[yDiffs.length ~/ 2] * 0.7).clamp(20.0, 80.0)
        : 34.0;

    // ── Step 2: 自适应找列分界线（centerX 最大 gap）
    // 只用数据区（页眉页脚无数据，噪声多）
    final dataBlocks = blocks.where((b) => b.avgY > 600 && b.avgY < 7500).toList();
    final allCX = dataBlocks.map((b) => b.centerX).toSet().toList()..sort();

    // 找最大 gap（>100px 才算有效列分界线，最多取 2 条）
    final gaps = <(double gap, double lo, double hi)>[];
    for (int i = 0; i < allCX.length - 1; i++) {
      final gap = allCX[i + 1] - allCX[i];
      if (gap >= 100) {
        gaps.add((gap, allCX[i], allCX[i + 1]));
      }
    }
    gaps.sort((a, b) => b.$1.compareTo(a.$1));

    // 取前两条 gap 的中点作为分界线
    List<double> splits;
    if (gaps.length >= 2) {
      splits = [
        (gaps[0].$2 + gaps[0].$3) / 2,
        (gaps[1].$2 + gaps[1].$3) / 2,
      ];
    } else if (gaps.length == 1) {
      splits = [(gaps[0].$2 + gaps[0].$3) / 2];
    } else {
      // Fallback: 固定分界线（支付宝两列布局典型值）
      splits = [480.0, 850.0];
    }
    splits.sort();

    // ── Step 3: 分列
    final cols = List.generate(splits.length + 1, (_) => <_OcrBlock>[]);
    for (final b in blocks) {
      int colIdx = 0;
      for (final s in splits) {
        if (b.centerX < s) break;
        colIdx++;
      }
      cols[colIdx].add(b);
    }

    // ── Step 4: 各列内按 Y 合并（返回 List<(avgY, mergedText)>）
    List<(double, String)> colMerge(List<_OcrBlock> col) {
      if (col.isEmpty) return [];
      col.sort((a, b) => a.avgY.compareTo(b.avgY));
      final rows = <List<_OcrBlock>>[];
      var cur = <_OcrBlock>[col.first];
      for (int i = 1; i < col.length; i++) {
        if ((col[i].avgY - cur.first.avgY).abs() < yThreshold) {
          cur.add(col[i]);
        } else {
          rows.add(cur);
          cur = [col[i]];
        }
      }
      rows.add(cur);
      return rows.map((row) {
        row.sort((a, b) => a.minX.compareTo(b.minX));
        final text = row.map((b) => b.text).where((t) => t.isNotEmpty).join('');
        return (row.first.avgY, text);
      }).toList();
    }

    final colRows = cols.map(colMerge).toList();

    // ── Step 5: 跨列按 Y 对齐拼接为单行（保持 V8 解析器输入格式）
    // 收集所有唯一 Y 值
    final allYs = <double>{};
    for (final cr in colRows) {
      for (final (y, _) in cr) allYs.add(y);
    }
    final sortedYs = allYs.toList()..sort();

    final lines = <String>[];
    for (final y in sortedYs) {
      // 从各列取 Y 最接近的行拼接
      final parts = <String>[];
      for (final cr in colRows) {
        final match = cr.firstWhere(
          (item) => (item.$1 - y).abs() < yThreshold,
          orElse: () => (0.0, ''),
        );
        if (match.$2.isNotEmpty) parts.add(match.$2);
      }
      if (parts.isNotEmpty) lines.add(parts.join(''));
    }

    // 去重：同一逻辑行因三列合并产生2-3个副本
    final uniqueLines = <String>[];
    for (final line in lines) {
      if (uniqueLines.isEmpty || line != uniqueLines.last) {
        uniqueLines.add(line);
      }
    }
    return uniqueLines.join('\n');
  }
  /// 例如：
  ///   "天弘恒生科技指数型发起式" + "证券投资基金(QDII)C"
  ///   → "天弘恒生科技指数型发起式证券投资基金(QDII)C"
  static String _smartMergeOcrLines(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return text;

    // 判断一行是否是"分隔线"（金额、数字、元数据关键词）
    bool isSeparator(String line) {
      if (RegExp(r'[¥￥]').hasMatch(line)) return true;
      if (RegExp(r'\d{1,3}(,\d{3})+\.\d{2}').hasMatch(line)) return true;
      // 裸数字金额：197.12 / 1,361.25 / 349.96（天天基金格式）
      if (RegExp(r'^[+-]?\d[\d,]*\.\d{2}$').hasMatch(line)) return true;
      // 纯数字收益行：+22.12 / -1.88 / +0.32
      if (RegExp(r'^[+-]\d[\d,]*\.\d{2}$').hasMatch(line)) return true;
      const metaKw = [
        '持有金额', '持有收益', '累计收益', '日收益', '昨日收益',
        '持有天数', '估值', '净值', '涨跌幅', '收益率', '操作',
        '确认', '买入', '卖出', '定投', '赎回', '转换', '排序',
        '全部', '我的', '持仓', '市值', '金额', '份额', '收益',
      ];
      for (final kw in metaKw) {
        if (line.length <= kw.length + 4 && line.contains(kw)) return true;
      }
      return false;
    }

    final result = <String>[];
    final buffer = <String>[];

    for (final line in lines) {
      if (isSeparator(line)) {
        // 遇到分隔线，把buffer里的内容合并后加入结果
        if (buffer.isNotEmpty) {
          result.add(buffer.join());
          buffer.clear();
        }
        result.add(line);
      } else {
        buffer.add(line);
      }
    }
    if (buffer.isNotEmpty) {
      result.add(buffer.join());
    }

    return result.join('\n');
  }

  /// iOS: MLKit 识别（iOS 上稳定）
  Future<String> _recognizeWithMlKit(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      if (!mounted) setState(() { _ocrProgress = 0.4; _ocrStatus = '识别文字中...'; });
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);
      return recognizedText.text;
    } finally {
      await recognizer.close();
    }
  }

  Future<Set<String>> _getExistingHoldingCodes() async {
    try {
      final repo = getIt<FundRepository>();
      final holdings = await repo.getHoldings();
      return holdings.map((h) => h.code).toSet();
    } catch (_) {
      return {};
    }
  }

    /// ══════════════════════════════════════════════════════════════
  /// 分段式匹配引擎
  /// 支付宝基金名结构：公司 + 板块/主题 + 类型 + 分类(A/C/...)
  /// 每段独立验证 → 组合命中越多置信度越高 → 趋近100%准确
  /// ══════════════════════════════════════════════════════════════

  /// 将OCR名称分解为各字段
  _FundNameSegments _parseOcrSegments(String name) {
    if (name.isEmpty) {
      return _FundNameSegments(company: '');
    }

    var s = name.trim();
    // 分类后缀（C / D / E / F...）
    String? suffix;
    if (s.length >= 2) {
      final lastChar = s[s.length - 1];
      if (RegExp(r'^[a-zA-Z]$').hasMatch(lastChar)) {
        suffix = lastChar;
        s = s.substring(0, s.length - 1);
      }
    }
    // 去除常见类型后缀（越往后越通用）
    const typeSuffixes = [
      '灵活配置混合', '定期开放债券', '混合型', '债券型', '货币型',
      '股票型', '指数型', 'lof', 'qdii', '混合', '债券', '货币', '发起式',
    ];
    String? typeTag;
    for (final t in typeSuffixes) {
      if (s.length > t.length && s.endsWith(t)) {
        typeTag = t;
        s = s.substring(0, s.length - t.length);
        break;
      }
    }
    // 板块特征词：长词优先匹配（越具体越准确）
    // ★ 排序：更长的特异性词优先，避免短词误匹配
    const featureWords = [
      // 长特征词（5字+）
      '恒生科技', '新能源车', '医疗服务', '医疗器械', '人工智能', '食品饮料',
      '有色金属', '绝对收益', '金银珠宝', '房地产', '纳斯达克', '标普500',
      '沪深300', '中证500', '中证1000', '高端制造', '先进制造',
      // 4字特征词
      '产业先锋', '优势产业', '新能源', '半导体', '光伏', '白酒',
      '创业板', '科创板', '互联网', '消费', '银行', '证券', '煤炭',
      // 3字特征词
      '碳中和', '新丝路', '低碳', '军工', '价值', '成长', '红利', '量化',
      // 2字特征词
      '港股', '美股', '互联', '优选', '精选', '农业', '家电', '汽车', '医药', '环保',
      '阿尔法',
    ];
    String? topic;
    for (final fw in featureWords) {
      if (s.contains(fw)) {
        topic = fw;
        break;
      }
    }
    // 公司名 = 去掉板块后的前缀（通常2-8字）
    // ★ 不再截断为4字 — 保留完整公司名以提高区分度
    String company = topic != null ? s.split(topic)[0] : s;
    company = company.trim();
    if (company.length > 8) company = company.substring(0, 8);
    return _FundNameSegments(
      company: company,
      topic: topic,
      typeTag: typeTag,
      suffix: suffix,
    );
  }

  /// 用各段组合搜索API，返回候选列表（按精度从高到低）
  Future<List<FundInfo>> _searchBySegments(_FundNameSegments seg) async {
    // 搜索关键词组合，按精度从高到低排列
    final List<String> keys = [];
    if (seg.company.isNotEmpty && seg.topic != null) {
      keys.addAll(['${seg.company}$seg.topic', seg.topic!, seg.company]);
    } else if (seg.topic != null) {
      keys.add(seg.topic!);
    } else if (seg.company.isNotEmpty) {
      keys.add(seg.company);
    }

    for (final key in keys) {
      if (key.length < 2) continue;
      try {
        final results = await getIt<FundRepository>()
            .searchFund(key)
            .timeout(const Duration(seconds: 5));
        if (results.isNotEmpty) return results;
      } catch (_) {}
    }
    return [];
  }

  /// 评分：各段独立命中得分，组合命中额外加分
  /// 得分 >= 4 表示高置信度，公司名必须命中
  int _scoreBySegments(_FundNameSegments seg, String apiName) {
    if (apiName.isEmpty) return 0;
    final company = seg.company;
    final topic = seg.topic;
    final typeTag = seg.typeTag;
    final suffix = seg.suffix;
    int score = 0;
    // 公司名命中 +5
    if (company.isNotEmpty && apiName.contains(company)) score += 5;
    // 板块特征词命中 +4
    if (topic != null && apiName.contains(topic)) score += 4;
    // 类型匹配 +2（模糊也 +1）
    if (typeTag != null) {
      if (apiName.contains(typeTag)) score += 2;
      else if (typeTag == '混合' && (apiName.contains('混合型') || apiName.contains('灵活配置'))) score += 1;
    }
    // 分类后缀命中（C/A/D）+2
    if (suffix != null && apiName.endsWith(suffix)) score += 2;
    // 公司+板块同时命中 → 强信号，+5
    if (company.isNotEmpty && topic != null
        && apiName.contains(company) && apiName.contains(topic)) score += 5;
    return score;
  }

  /// 计算两个名字的字符级重合度（用于同分 tiebreaker）
  /// 返回匹配的字符数
  static int _charOverlap(String ocrName, String apiName) {
    if (ocrName.isEmpty || apiName.isEmpty) return 0;
    int overlap = 0;
    final apiChars = apiName.split('');
    for (final ch in ocrName.split('')) {
      if (apiChars.contains(ch)) overlap++;
    }
    return overlap;
  }

  Future<List<_EnhancedHoldingItem>> _enhanceHoldings(
      List<RecognizedHolding> parsed, Set<String> existingCodes) async {
    // 并行处理所有基金
    final items = await Future.wait(
      parsed.map((h) async {
        final item = _EnhancedHoldingItem(
          code: h.code, name: h.name, amount: h.amount,
          confidence: h.confidence, needsCodeMatch: h.needsCodeMatch,
          selected: h.amount > 0,
          operationType: existingCodes.contains(h.code)
              ? ImportOperationType.add
              : ImportOperationType.sync,
        );

        try {
          // 有代码 → 精确搜代码
          if (h.code.isNotEmpty) {
            final results = await getIt<FundRepository>()
                .searchFund(h.code)
                .timeout(const Duration(seconds: 5));
            if (results.isNotEmpty) {
              final match = results.first;
              item.fundCode = match.code;
              item.fundName = match.name;
              item.code = match.code;
              item.needsCodeMatch = false;
              if (match.name.length > item.name.length) item.name = match.name;
            }
          }
          // 无代码 → 分段式搜索
          else if (h.name.length >= 3) {
            final seg = _parseOcrSegments(h.name);
            final results = await _searchBySegments(seg);
            if (results.isNotEmpty) {
              // 从候选中选得分最高的
              int bestIdx = 0, bestScore = 0;
              for (int i = 0; i < results.length; i++) {
                try {
                  final s = _scoreBySegments(seg, results[i].name);
                  // 同分用全名字符重合度做 tiebreaker
                  if (s > bestScore) {
                    bestScore = s; bestIdx = i;
                  } else if (s == bestScore && bestScore > 0) {
                    // 计算与OCR名的字符重合度（更精准的区分）
                    final curOverlap = _charOverlap(h.name, results[i].name);
                    final bestOverlap = _charOverlap(h.name, results[bestIdx].name);
                    if (curOverlap > bestOverlap) { bestIdx = i; }
                  }
                } catch (_) {}
              }
              // 公司名必须命中，否则匹配不可靠
              if (bestScore >= 4 && bestIdx < results.length) {
                final match = results[bestIdx];
                item.fundCode = match.code;
                item.fundName = match.name;
                item.code = match.code;
                item.needsCodeMatch = false;
                if (match.name.length > item.name.length) item.name = match.name;
              }
            }
          }
        } catch (_) {}

        return item;
      }),
    );

    return items;
  }

// ── 步骤3：预览确认 ────────────────────────────────────────
  Widget _buildPreviewStep() {
    return Column(
      children: [
        // ═══ 调试面板：原始OCR文本 ══════════════════════
        if (_rawOcrText.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5DC),
              border: Border.all(color: const Color(0xFFCCCC00)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔍 OCR原始文本（调试）',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: Color(0xFF666600))),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: SelectableText(_rawOcrText,
                        style: const TextStyle(fontSize: 11,
                            color: Color(0xFF333300), fontFamily: 'monospace')),
                  ),
                ),
              ],
            ),
          ),
        // ═══ 记录计数条 ═══════════════════════════════
        Container(
          padding: const EdgeInsets.all(12),
          color: AppTheme.bgSecondary,
          child: Row(
            children: [
              Text('识别到 ${_holdings.length} 条记录',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              const Spacer(),
              TextButton(onPressed: _toggleSelectAll,
                  child: Text(_selectAll ? '取消全选' : '全选')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _holdings.length,
            itemBuilder: (ctx, i) => _buildHoldingItem(i),
          ),
        ),
        Container(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 12,
            bottom: 12 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            border: Border(top: BorderSide(color: AppTheme.borderColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step = _ImportStep.upload),
                  child: const Text('重新选择'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _selectedCount > 0 ? _confirmImport : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('导入 ${_selectedCount} 只'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int get _selectedCount => _holdings.where((h) => h.selected && h.amount > 0).length;

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      for (final h in _holdings) {
        // 有金额的都可以选，不管有没有代码
        if (h.amount > 0) h.selected = _selectAll;
      }
    });
  }

  Widget _buildHoldingItem(int index) {
    final h = _holdings[index];
    final isConvert = h.operationType == ImportOperationType.convert;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: h.selected ? AppTheme.primary : AppTheme.borderColor,
          width: h.selected ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        children: [
          // 主内容
          InkWell(
            onTap: () {
              // 有金额就能选，没代码的展示搜索
              if (h.amount > 0) {
                setState(() => h.selected = !h.selected);
              }
              if (h.code.isEmpty) {
                setState(() => h.showSearch = !h.showSearch);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: h.selected,
                    onChanged: h.amount > 0
                        ? (v) => setState(() => h.selected = v ?? false)
                        : null,
                    activeColor: AppTheme.primary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                h.name.isNotEmpty ? h.name : (h.fundName ?? '未知基金'),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (h.code.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(h.code,
                                    style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildConfidenceBadge(h.confidence),
                            if (h.needsCodeMatch && h.code.isEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('需匹配',
                                    style: TextStyle(fontSize: 11, color: Colors.orange)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 70,
                          child: TextField(
                            controller: h.amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: AppTheme.borderColor),
                              ),
                            ),
                            onChanged: (v) {
                              final amount = double.tryParse(v) ?? 0;
                              setState(() => h.amount = amount);
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('元', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 操作类型选择
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: SegmentedButton<ImportOperationType>(
                        segments: const [
                          ButtonSegment(value: ImportOperationType.sync,
                              label: Text('同步', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: ImportOperationType.add,
                              label: Text('加仓', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: ImportOperationType.reduce,
                              label: Text('减仓', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: ImportOperationType.convert,
                              label: Text('转换', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {h.operationType},
                        onSelectionChanged: (v) =>
                            setState(() => h.operationType = v.first),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
                // 转换时显示目标基金输入
                if (isConvert) _buildConvertTarget(h),
              ],
            ),
          ),
          // 搜索面板
          if (h.showSearch) _buildSearchPanel(h),
        ],
      ),
    );
  }

  /// 转换目标基金输入
  Widget _buildConvertTarget(_EnhancedHoldingItem h) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text('转换至目标基金',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: h.targetController,
            decoration: InputDecoration(
              hintText: '输入目标基金代码或名称搜索',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: h.targetSearching
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (h.targetCode.isNotEmpty
                      ? const Icon(Icons.check_circle, color: AppTheme.downColor, size: 20)
                      : const SizedBox.shrink()),
            ),
            onChanged: (v) => _searchTargetFund(h, v),
          ),
          if (h.targetSearchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: h.targetSearchResults.length,
                itemBuilder: (_, i) {
                  final r = h.targetSearchResults[i];
                  // 排除源基金
                  if (r.code == h.code) return const SizedBox.shrink();
                  return ListTile(
                    dense: true,
                    title: Text(r.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(r.code, style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () {
                      setState(() {
                        h.targetCode = r.code;
                        h.targetName = r.name;
                        h.targetSearchResults = [];
                        h.targetController.text = '${r.name} (${r.code})';
                      });
                    },
                  );
                },
              ),
            ),
          if (h.targetCode.isNotEmpty && h.targetCode == h.code)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⚠️ 目标基金不能与源基金相同',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
            ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(double confidence) {
    Color color;
    if (confidence >= 0.8) {
      color = AppTheme.downColor;
    } else if (confidence >= 0.5) {
      color = Colors.orange;
    } else {
      color = AppTheme.upColor;
    }
    return Text(
      '置信度 ${(confidence * 100).toStringAsFixed(0)}%',
      style: TextStyle(fontSize: 11, color: color),
    );
  }

  Widget _buildSearchPanel(_EnhancedHoldingItem h) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary,
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        children: [
          TextField(
            controller: h.searchController,
            decoration: InputDecoration(
              hintText: '输入基金名称或代码搜索',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: h.searching
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: (v) => _searchFund(h, v),
          ),
          if (h.searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: h.searchResults.length,
                itemBuilder: (_, i) {
                  final r = h.searchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(r.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(r.code, style: const TextStyle(fontSize: 11)),
                    onTap: () => _selectSearchResult(h, r),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _searchFund(_EnhancedHoldingItem h, String query) async {
    if (query.trim().isEmpty) return;
    setState(() => h.searching = true);
    try {
      final repo = getIt<FundRepository>();
      final results = await repo.searchFund(query);
      setState(() {
        h.searchResults = results;
        h.searching = false;
      });
    } catch (e) {
      debugPrint('[_searchFund] 搜索 "$query" 失败: $e');
      setState(() => h.searching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('搜索失败，请检查网络后重试'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _searchTargetFund(_EnhancedHoldingItem h, String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      h.targetCode = '';
      h.targetName = '';
      h.targetSearching = true;
    });
    try {
      final repo = getIt<FundRepository>();
      final results = await repo.searchFund(query);
      setState(() {
        h.targetSearchResults = results;
        h.targetSearching = false;
      });
    } catch (e) {
      debugPrint('[_searchTargetFund] 搜索 "$query" 失败: $e');
      setState(() => h.targetSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('搜索失败，请检查网络后重试'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _selectSearchResult(_EnhancedHoldingItem h, FundInfo result) {
    setState(() {
      h.code = result.code;
      h.fundCode = result.code;
      h.fundName = result.name;
      if (h.name.isEmpty) h.name = result.name;
      h.needsCodeMatch = false;
      h.selected = true;
      h.showSearch = false;
      h.searchResults = [];
    });
  }

  // ── 步骤4：导入中 ──────────────────────────────────────────
  Widget _buildImportingStep() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在导入...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Future<void> _confirmImport() async {
    // 验证转换项的目标基金
    for (final h in _holdings.where((h) => h.selected && h.operationType == ImportOperationType.convert)) {
      if (h.targetCode.isEmpty) {
        _showError('转换项 "${h.name}" 未选择目标基金');
        return;
      }
      if (h.targetCode == h.code) {
        _showError('转换项 "${h.name}" 目标基金不能与源基金相同');
        return;
      }
    }

    // 验证必须有代码（支付宝截图没有代码，提示用户先搜索匹配）
    final noCode = _holdings.where((h) => h.selected && h.amount > 0 && h.code.isEmpty).toList();
    if (noCode.isNotEmpty) {
      _showError('${noCode.length} 条记录缺少基金代码，请点击展开搜索匹配');
      return;
    }

    // 验证名称完整性（名称太短说明OCR截断，数据不可靠）
    final shortName = _holdings.where((h) =>
        h.selected && h.amount > 0 && h.code.isNotEmpty &&
        (h.fundName ?? h.name).length < 4).toList();
    if (shortName.isNotEmpty) {
      final names = shortName.map((h) => '"${h.fundName ?? h.name}"').join('、');
      _showError('以下记录名称过短，请手动搜索匹配：$names');
      return;
    }

    final toImport = _holdings.where((h) => h.selected && h.amount > 0 && h.code.isNotEmpty).toList();
    if (toImport.isEmpty) {
      _showError('请选择要导入的持仓');
      return;
    }

    setState(() => _step = _ImportStep.importing);

    try {
      final bloc = context.read<HoldingsBloc>();
      final repo = getIt<FundRepository>();
      final existingHoldings = await repo.getHoldings();
      final existingMap = {for (var h in existingHoldings) h.code: h};

      int imported = 0, added = 0, reduced = 0, converted = 0;

      for (final h in toImport) {
        final netValue = h.netValue ?? 1.0;
        final shares = h.amount / netValue;

        switch (h.operationType) {
          case ImportOperationType.sync:
            _syncHolding(bloc, h, netValue, shares);
            imported++;
            break;

          case ImportOperationType.add:
            _addHolding(bloc, h, existingMap, netValue, shares);
            added++;
            break;

          case ImportOperationType.reduce:
            _reduceHolding(bloc, h, existingMap, netValue, shares);
            reduced++;
            break;

          case ImportOperationType.convert:
            if (h.targetCode.isNotEmpty) {
              _convertHolding(bloc, h, existingMap, netValue, shares, repo);
              converted++;
            }
            break;
        }
      }

      if (!mounted) return;

      String msg = '';
      if (imported > 0) msg += '新增 $imported ';
      if (added > 0) msg += '加仓 $added ';
      if (reduced > 0) msg += '减仓 $reduced ';
      if (converted > 0) msg += '转换 $converted ';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.trim()), behavior: SnackBarBehavior.floating),
      );

      context.pop();
    } catch (e) {
      if (!mounted) return;
      _showError('导入失败: $e');
      setState(() => _step = _ImportStep.preview);
    }
  }

  void _syncHolding(HoldingsBloc bloc, _EnhancedHoldingItem h, double netValue, double shares) {
    final record = HoldingRecord(
      code: h.code,
      name: h.name.isNotEmpty ? h.name : (h.fundName ?? h.code),
      shareClass: _detectShareClass(h.code, h.name),
      amount: h.amount,
      buyNetValue: netValue,
      shares: shares,
      buyDate: DateTime.now().toIso8601String().split('T')[0],
      holdingDays: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    bloc.add(HoldingsAdd(record));
  }

  void _addHolding(HoldingsBloc bloc, _EnhancedHoldingItem h,
      Map<String, HoldingRecord> existingMap, double netValue, double shares) {
    final existing = existingMap[h.code];
    if (existing != null) {
      final newAmount = existing.amount + h.amount;
      final newShares = existing.shares + shares;
      final avgNav = newShares > 0 ? newAmount / newShares : netValue;
      final record = HoldingRecord(
        code: h.code, name: existing.name, shareClass: existing.shareClass,
        amount: newAmount, buyNetValue: avgNav, shares: newShares,
        buyDate: existing.buyDate, holdingDays: existing.holdingDays,
        createdAt: existing.createdAt,
      );
      bloc.add(HoldingsAdd(record));
    } else {
      _syncHolding(bloc, h, netValue, shares);
    }
  }

  void _reduceHolding(HoldingsBloc bloc, _EnhancedHoldingItem h,
      Map<String, HoldingRecord> existingMap, double netValue, double shares) {
    final existing = existingMap[h.code];
    if (existing != null) {
      final newAmount = existing.amount - h.amount;
      if (newAmount <= 0) {
        bloc.add(HoldingsDelete(h.code));
      } else {
        final newShares = existing.shares - shares;
        final record = HoldingRecord(
          code: h.code, name: existing.name, shareClass: existing.shareClass,
          amount: newAmount, buyNetValue: existing.buyNetValue,
          shares: newShares > 0 ? newShares : 0,
          buyDate: existing.buyDate, holdingDays: existing.holdingDays,
          createdAt: existing.createdAt,
        );
        bloc.add(HoldingsAdd(record));
      }
    }
  }

  Future<void> _convertHolding(HoldingsBloc bloc, _EnhancedHoldingItem h,
      Map<String, HoldingRecord> existingMap, double netValue, double shares,
      FundRepository repo) async {
    // 1. 源基金减仓
    final sourceExisting = existingMap[h.code];
    if (sourceExisting != null) {
      final newAmount = sourceExisting.amount - h.amount;
      if (newAmount <= 0) {
        bloc.add(HoldingsDelete(h.code));
      } else {
        final newShares = sourceExisting.shares - shares;
        bloc.add(HoldingsAdd(HoldingRecord(
          code: h.code, name: sourceExisting.name, shareClass: sourceExisting.shareClass,
          amount: newAmount, buyNetValue: sourceExisting.buyNetValue,
          shares: newShares > 0 ? newShares : 0,
          buyDate: sourceExisting.buyDate, holdingDays: sourceExisting.holdingDays,
          createdAt: sourceExisting.createdAt,
        )));
      }
    }

    // 2. 目标基金加仓（用同一净值估算）
    final targetExisting = existingMap[h.targetCode];
    if (targetExisting != null) {
      final newAmount = targetExisting.amount + h.amount;
      final newShares = targetExisting.shares + shares;
      final avgNav = newShares > 0 ? newAmount / newShares : netValue;
      bloc.add(HoldingsAdd(HoldingRecord(
        code: h.targetCode, name: targetExisting.name, shareClass: targetExisting.shareClass,
        amount: newAmount, buyNetValue: avgNav, shares: newShares,
        buyDate: targetExisting.buyDate, holdingDays: targetExisting.holdingDays,
        createdAt: targetExisting.createdAt,
      )));
    } else {
      // 目标基金不存在，新增
      bloc.add(HoldingsAdd(HoldingRecord(
        code: h.targetCode,
        name: h.targetName,
        shareClass: 'A',
        amount: h.amount,
        buyNetValue: netValue,
        shares: shares,
        buyDate: DateTime.now().toIso8601String().split('T')[0],
        holdingDays: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      )));
    }
  }

  /// 检测份额类别：从基金名尾部或代码最后一个字符识别
  static const _shareClasses = {'A','B','C','D','E','F','H','I','R','Y'};
  String _detectShareClass(String code, String name) {
    // 先从基金名尾部识别
    final nameLast = name[name.length - 1].toUpperCase();
    if (_shareClasses.contains(nameLast)) return nameLast;
    // 再从代码尾部识别
    final codeLast = code[code.length - 1].toUpperCase();
    if (_shareClasses.contains(codeLast)) return codeLast;
    return 'A'; // 默认 A 类
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.upColor),
    );
  }
}

// ── 内部类 ──────────────────────────────────────────────────
enum _ImportStep { upload, recognizing, preview, importing }

/// 增强的持仓项（用于UI）
class _EnhancedHoldingItem {
  String code;
  String name;
  double amount;
  double confidence;
  bool needsCodeMatch;
  bool selected;
  ImportOperationType operationType;
  String? fundCode;
  String? fundName;
  double? netValue;
  bool showSearch = false;
  bool searching = false;
  List<FundInfo> searchResults = [];

  // 转换专用
  String targetCode = '';  // 目标基金代码
  String targetName = '';  // 目标基金名称
  bool targetSearching = false;
  List<FundInfo> targetSearchResults = [];

  final amountController = TextEditingController();
  final searchController = TextEditingController();
  final targetController = TextEditingController();

  _EnhancedHoldingItem({
    required this.code,
    required this.name,
    required this.amount,
    this.confidence = 0.5,
    this.needsCodeMatch = false,
    this.selected = false,
    this.operationType = ImportOperationType.sync,
  }) {
    amountController.text = amount > 0 ? amount.toStringAsFixed(2) : '';
  }
}

class _UploadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UploadButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.primary),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
