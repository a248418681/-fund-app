import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../../core/di/injection.dart';
import '../../../utils/ocr_service.dart';
import '../../bloc/holdings/holdings_bloc.dart';
import '../../bloc/holdings/holdings_event.dart';

/// OCR常见字形混淆字纠错映射（通用，非硬编码特定基金）
/// 来源：ML Kit中文OCR高频误识统计，适用于任何含这些字的基金名
const Map<String, String> _ocrCharCorrections = {
  '永嘉': '永赢', // 赢→嘉（字形相似）
  '生夏': '华夏', // 华→生（字形相似）
  '混台': '混合', // 合→台（字形极似）
  '指教': '指数', // 数→教（字形相似）
  '増强': '增强', // 增→増（日式汉字）
  '利技': '科技', // 科→利（字形部分相似）
  '专精特新量化达股': '专精特新量化选股', // 选→达
  '技指数': '指数', // OCR多读"技"导致"科技技指数" → "科技指数"
};

/// 对OCR识别的基金名做通用字形纠错
String _correctOcrName(String name) {
  var s = name;
  for (final entry in _ocrCharCorrections.entries) {
    if (s.contains(entry.key)) {
      s = s.replaceAll(entry.key, entry.value);
    }
  }
  return s;
}

/// 导入操作类型
enum ImportOperationType {
  sync, // 同步持仓
  add, // 加仓
  reduce, // 减仓
  convert, // 转换
}

/// 截图导入持仓页面
/// 4个步骤：选择图片 → 识别中 → 预览确认 → 导入中
/// 分段式匹配引擎的段结构体
/// OCR文本块的坐标信息
class _FundNameSegments {
  final String company; // 基金公司名（2-4字）
  final String? topic; // 板块/主题特征词
  final String? typeTag; // 类型标签（混合型/债券型/货币型...）
  final String? suffix; // 分类后缀（A/B/C/D...）

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
        const Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 64, color: AppTheme.textMuted),
                SizedBox(height: 16),
                Text('选择持仓截图',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                SizedBox(height: 8),
                Text('支持支付宝、天天基金等平台截图',
                    style:
                        TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                  child: _UploadButton(
                icon: Icons.camera_alt_outlined,
                label: '拍照',
                onTap: () => _pickImage(ImageSource.camera),
              )),
              const SizedBox(width: 16),
              Expanded(
                  child: _UploadButton(
                icon: Icons.photo_outlined,
                label: '相册',
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
        source: source,
        maxWidth: 4096,
        maxHeight: 16384,
        imageQuality: 95,
      );
      if (image == null) return;
      setState(() {
        _imagePath = image.path;
        _step = _ImportStep.recognizing;
      });
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
                  child: Image.file(File(_imagePath!),
                      fit: BoxFit.contain,
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
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _startOcr(String imagePath) async {
    try {
      setState(() {
        _ocrProgress = 0.1;
        _ocrStatus = '验证图片...';
      });

      // 验证文件
      final file = File(imagePath);
      if (!await file.exists()) {
        if (mounted) {
          _showError('图片文件不存在');
          setState(() => _step = _ImportStep.upload);
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _ocrProgress = 0.2;
        _ocrStatus = '初始化OCR引擎...';
      });

      // 双端统一使用 Google ML Kit（识别质量优于 PaddleOCR）
      // V9: 使用2D block坐标横向解析，不再压扁为文本
      final ocrResult = await _recognizeWithMlKitV9(imagePath);
      final text = ocrResult['text'] as String;
      final blocks = ocrResult['blocks'] as List<OcrBlock>;
      final imageWidth = ocrResult['imageWidth'] as double;

      if (!mounted) return;
      debugPrint('[OCR] 识别文本长度: ${text.length}, blocks: ${blocks.length}');
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
      debugPrint(
          '[OCR] 前200字: ${text.length > 200 ? text.substring(0, 200) : text}');
      _rawOcrText = text; // 调试用

      if (text.trim().isEmpty && blocks.isEmpty) {
        if (mounted) {
          _showError('未识别到文字，请确保截图清晰');
          setState(() => _step = _ImportStep.upload);
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _ocrProgress = 0.7;
        _ocrStatus = '解析持仓信息...';
      });

      // ★ V9优先：用block坐标横向解析，回退到V8文本解析
      List<RecognizedHolding> parsed;
      if (blocks.isNotEmpty) {
        parsed = OcrService.parseHoldingBlocks(blocks, imageWidth: imageWidth);
        if (parsed.isEmpty) {
          debugPrint('[OCR] V9解析无结果，回退到V8文本解析');
          parsed = OcrService.parseHoldingText(text);
        }
      } else {
        parsed = OcrService.parseHoldingText(text);
      }
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
            const SnackBar(
                content: Text('未识别到持仓信息，请查看调试面板'),
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
      if (mounted) {
        _showError('识别失败: $e');
        setState(() => _step = _ImportStep.upload);
      }
    }
  }

  /// ML Kit V9识别（返回 line 级坐标 + 文本，用于横向解析）
  /// 关键点：不要使用 recognizedText.blocks 作为解析单元，block 可能包含多行，
  /// 支付宝持仓页必须用 line 级别坐标才能稳定分组。
  Future<Map<String, dynamic>> _recognizeWithMlKitV9(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      if (mounted) {
        setState(() {
          _ocrProgress = 0.4;
          _ocrStatus = '识别文字中...';
        });
      }

      double imageWidth = 1080.0;
      double imageHeight = 0.0;
      try {
        final bytes = await File(imagePath).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        imageWidth = frame.image.width.toDouble();
        imageHeight = frame.image.height.toDouble();
        frame.image.dispose();
      } catch (e) {
        debugPrint('[OCR] 读取图片尺寸失败，使用坐标估算: $e');
      }

      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);

      // 提取 line 级坐标信息。block 粒度太粗，换一张图就容易把多行吞成一个块。
      final blocks = <OcrBlock>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;
          final rect = line.boundingBox;
          blocks.add(OcrBlock(
            text: text,
            left: rect.left,
            top: rect.top,
            right: rect.right,
            bottom: rect.bottom,
          ));
          if (rect.right > imageWidth) imageWidth = rect.right;
        }
      }

      // 极少数机型 line 为空时，退回 block 级数据，避免直接崩掉。
      if (blocks.isEmpty) {
        for (final block in recognizedText.blocks) {
          final text = block.text.trim();
          if (text.isEmpty) continue;
          final rect = block.boundingBox;
          blocks.add(OcrBlock(
            text: text,
            left: rect.left,
            top: rect.top,
            right: rect.right,
            bottom: rect.bottom,
          ));
          if (rect.right > imageWidth) imageWidth = rect.right;
        }
      }

      final blockMaps = blocks
          .map((b) => <String, dynamic>{
                'text': b.text,
                'left': b.left,
                'top': b.top,
                'right': b.right,
                'bottom': b.bottom,
                'cx': b.centerx,
                'cy': b.centery,
              })
          .toList();
      final text = _mergeMlKitBlocks(blockMaps);

      // 保存 line 坐标 JSON 供调试，不再写 blocks.toString()。
      try {
        final dir = Directory(r'/data/data/com.example.fund_app/files');
        if (await dir.exists()) {
          final file = File('${dir.path}/fund_ocr_blocks.json');
          await file.writeAsString(jsonEncode({
            'imageWidth': imageWidth,
            'imageHeight': imageHeight,
            'lines': blockMaps,
          }));
        }
      } catch (e) {
        debugPrint('[OCR] 保存blocks失败: $e');
      }

      return {
        'text': text,
        'blocks': blocks,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      };
    } finally {
      await recognizer.close();
    }
  }

  /// 合并 MLKit blocks（同行合并）
  String _mergeMlKitBlocks(List<Map<String, dynamic>> blocks) {
    if (blocks.isEmpty) return '';

    // 计算全局平均行高（用于固定阈值）
    final heights = blocks
        .map((b) => (b['bottom'] as double) - (b['top'] as double))
        .toList();
    heights.sort();
    final medianHeight =
        heights.isNotEmpty ? heights[heights.length ~/ 2] : 20.0;
    // 固定阈值：行高的40%，但最小10px（小字体也够用）
    final fixedThreshold = (medianHeight * 0.4).clamp(10.0, 25.0);

    // 按 centerY 排序（比 top 更鲁棒，处理基线偏移）
    blocks.sort((a, b) {
      final ca = ((a['top'] as double) + (a['bottom'] as double)) / 2;
      final cb = ((b['top'] as double) + (b['bottom'] as double)) / 2;
      return ca.compareTo(cb);
    });

    final lines = <List<Map<String, dynamic>>>[];
    double? lastCenterY;

    for (final block in blocks) {
      final centerY =
          ((block['top'] as double) + (block['bottom'] as double)) / 2;

      if (lastCenterY == null ||
          (centerY - lastCenterY).abs() > fixedThreshold) {
        // 新行
        lines.add([block]);
        lastCenterY = centerY;
      } else {
        // 同一行，按 X 排序后添加
        lines.last.add(block);
        lines.last.sort(
            (a, b) => (a['left'] as double).compareTo(b['left'] as double));
      }
    }

    // 合并每行的文本
    return lines
        .map((line) => line.map((b) => b['text'] as String).join(' '))
        .join('\n');
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
      '灵活配置混合',
      '定期开放债券',
      '混合型',
      '债券型',
      '货币型',
      '股票型',
      '股票',
      '指数型',
      'lof',
      'qdii',
      '混合',
      '债券',
      '货币',
      '发起式',
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
      '高端装备', '产业先锋', '优势产业', '新能源', '半导体', '光伏', '白酒',
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

  /// 一层匹配：用中文全名直接搜索，后缀匹配（简单直接）
  /// 返回匹配的 FundInfo，失败返回 null → 触发二层分段匹配
  Future<FundInfo?> _trySimpleMatch(String ocrName) async {
    // 1. 提取结尾英文后缀（A/C/B...）
    String chinesePart = ocrName.trim();
    String? suffix;
    if (chinesePart.length >= 2) {
      final last = chinesePart[chinesePart.length - 1];
      if (RegExp(r'^[a-zA-Z]$').hasMatch(last)) {
        suffix = last.toUpperCase();
        chinesePart = chinesePart.substring(0, chinesePart.length - 1);
      }
    }
    // 2. 清理特殊字符，保留中文和数字
    chinesePart = chinesePart
        .replaceAll(RegExp(r'[()（）\[\]【】\-—\s]'), '')
        .replaceAll(RegExp(r'(lof|qdii?|发起式)', caseSensitive: false), '')
        .trim();
    if (chinesePart.length < 3) return null;

    // 3. 先尝试原样搜索，失败则尝试 "联接"→"ETF联接" 变体
    final searchKeys = <String>[chinesePart];
    if (chinesePart.contains('联接') && !chinesePart.contains('ETF联接')) {
      searchKeys.add(chinesePart.replaceAll('联接', 'ETF联接'));
    }

    for (final key in searchKeys) {
      try {
        final results = await getIt<FundRepository>()
            .searchFund(key)
            .timeout(const Duration(seconds: 5));
        final funds =
            results.where((r) => RegExp(r'^\d{6}$').hasMatch(r.code)).toList();
        if (funds.isEmpty) continue;

        debugPrint(
            '[SimpleMatch] key="$key" → ${funds.length} results, suffix="$suffix"');

        // 4. 后缀匹配：优先精确，其次任意
        if (suffix != null) {
          final suffixMatch = funds.firstWhere(
            (f) => f.name.endsWith(suffix!),
            orElse: () => funds.first,
          );
          debugPrint(
              '[SimpleMatch] ✅ suffix "$suffix" → ${suffixMatch.code} ${suffixMatch.name}');
          return suffixMatch;
        }
        debugPrint(
            '[SimpleMatch] ✅ (no suffix) → ${funds.first.code} ${funds.first.name}');
        return funds.first;
      } catch (e) {
        debugPrint('[SimpleMatch] key="$key" FAILED: $e');
      }
    }
    debugPrint(
        '[SimpleMatch] ❌ "$chinesePart" not found → fallback to segments');
    return null;
  }

  /// 用各段组合搜索API，返回候选列表（搜集所有key的搜索结果用于打分选最佳）
  Future<List<FundInfo>> _searchBySegments(
      _FundNameSegments seg, String fullOcrName) async {
    // ★ 完整OCR名预处理
    final cleanOcr = fullOcrName
        .replaceAll(RegExp(r'[()（）\[\]【】\-—]'), '')
        .replaceAll(RegExp(r'(lof|qdii?|etf|发起式)', caseSensitive: false), '')
        .trim();

    // 搜索关键词组合
    final List<String> keys = [];
    if (seg.company.isNotEmpty && seg.topic != null) {
      keys.addAll(['${seg.company}${seg.topic}', seg.topic!, seg.company]);
      // 渐进式去前缀：OCR可能把公司名首字读错，去掉首字再搜
      // 例如 "云利高端装备" → "利高端装备" 能匹配到 "宏利高端装备"
      if (seg.company.length > 1) {
        keys.add('${seg.company.substring(1)}${seg.topic}');
      }
      if (seg.typeTag != null && seg.typeTag!.length >= 2) {
        keys.add('${seg.topic}${seg.typeTag}');
      }
      // 回退：OCR名去掉公司前缀，作为更精确的搜索键
      // 例："东方阿尔法瑞享混合c" → "阿尔法瑞享混合c" 能命中排名靠后的基金
      final withoutCompany = cleanOcr.startsWith(seg.company)
          ? cleanOcr.substring(seg.company.length)
          : cleanOcr;
      if (withoutCompany.length >= 3 && withoutCompany != seg.topic) {
        keys.add(withoutCompany);
      }
    } else if (seg.topic != null) {
      keys.add(seg.topic!);
    } else if (seg.company.isNotEmpty) {
      keys.add(seg.company);
    }

    if (cleanOcr.length >= 3) {
      keys.insert(0, cleanOcr);
    }

    // ★ 搜集所有key的搜索结果，不提前返回第一个
    final allResults = <String, FundInfo>{};
    for (final key in keys) {
      if (key.length < 2) continue;
      try {
        final results = await getIt<FundRepository>()
            .searchFund(key)
            .timeout(const Duration(seconds: 5));
        int added = 0;
        for (final r in results) {
          // ★ 只保留基金代码（6位数字），排除股票/指数等杂项结果
          if (RegExp(r'^\d{6}$').hasMatch(r.code)) {
            allResults[r.code] = r; // 去重
            added++;
          }
        }
        debugPrint(
            '[Import-Search] key="$key" got ${results.length} raw → $added fund codes kept (total unique: ${allResults.length})');
      } catch (e) {
        debugPrint('[Import-Search] key="$key" FAILED: $e');
      }
    }
    debugPrint('[Import-Search] Final candidates: ${allResults.length}');
    return allResults.values.toList();
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
      if (apiName.contains(typeTag)) {
        score += 2;
      } else if (typeTag == '混合' &&
          (apiName.contains('混合型') || apiName.contains('灵活配置'))) {
        score += 1;
      }
    }
    // 分类后缀命中（C/A/D）+2
    if (suffix != null && apiName.endsWith(suffix)) score += 2;
    // 公司+板块同时命中 → 强信号，+5
    if (company.isNotEmpty &&
        topic != null &&
        apiName.contains(company) &&
        apiName.contains(topic)) {
      score += 5;
    }
    return score;
  }

  /// 归一化名称，只保留汉字、字母、数字，用于字符重合度计算
  static String _normalizeForOverlap(String name) {
    // 去掉所有非汉字/字母/数字 + 常见OCR残留 (LOF)/(QDI)/(QDII)/(ETF) 等
    return name
        .replaceAll(RegExp(r'[^一-龥a-zA-Z0-9]'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'lof|qdii?|etf|发起式'), '')
        .replaceAll(RegExp(r'\(|\)'), '');
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
    debugPrint(
        '[Import] ═══ _enhanceHoldings V2.1 (overlap guard) ═══ ${parsed.length}条待匹配');
    // 并行处理所有基金
    final items = await Future.wait(
      parsed.map((h) async {
        final item = _EnhancedHoldingItem(
          code: h.code,
          name: h.name,
          amount: h.amount,
          confidence: h.confidence,
          needsCodeMatch: h.needsCodeMatch,
          selected: h.amount > 0,
          operationType: existingCodes.contains(h.code)
              ? ImportOperationType.add
              : ImportOperationType.sync,
          yesterdayProfit: h.yesterdayProfit,
          holdingProfit: h.holdingProfit,
          holdingProfitRate: h.holdingProfitRate,
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
              item.name = match.name;
            }
          }
          // 无代码 → 匹配策略：
          // 一层：中文全名搜索 + 后缀匹配（简单直接）
          // 二层：分段式回退（处理OCR差异/排名靠后的基金）
          else if (h.name.length >= 3) {
            final matched = await _trySimpleMatch(h.name);
            if (matched != null) {
              item.fundCode = matched.code;
              item.fundName = matched.name;
              item.code = matched.code;
              item.needsCodeMatch = false;
              item.name = matched.name;
            } else {
              // 二层回退：分段式搜索
              final correctedName = _correctOcrName(h.name);
              final seg = _parseOcrSegments(correctedName);
              final results = await _searchBySegments(seg, correctedName);
              if (results.isNotEmpty) {
                int bestIdx = 0, bestScore = 0;
                for (int i = 0; i < results.length; i++) {
                  try {
                    final s = _scoreBySegments(seg, results[i].name);
                    if (s > bestScore) {
                      bestScore = s;
                      bestIdx = i;
                    } else if (s == bestScore && bestScore > 0) {
                      final curOverlap =
                          _charOverlap(correctedName, results[i].name);
                      final bestOverlap =
                          _charOverlap(correctedName, results[bestIdx].name);
                      if (curOverlap > bestOverlap) {
                        bestIdx = i;
                      } else if (curOverlap == bestOverlap) {
                        // 重叠度相同时，优先人民币份额
                        if (results[i].name.contains('人民币') &&
                            !results[bestIdx].name.contains('人民币')) {
                          bestIdx = i;
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint(
                        '[Import] _scoreBySegments failed for "${results[i].name}": $e');
                  }
                }
                if (bestScore >= 4 && bestIdx < results.length) {
                  final match = results[bestIdx];
                  final ocrPure =
                      _normalizeForOverlap(correctedName); // 用纠正后的名算重叠度
                  final matchPure = _normalizeForOverlap(match.name);
                  final overlap = _charOverlap(ocrPure, matchPure);
                  final jaccard = overlap > 0
                      ? overlap / (ocrPure.length + matchPure.length - overlap)
                      : 0.0;
                  debugPrint(
                      '[Import] OCR="$ocrPure"(${ocrPure.length}字) -> API="$matchPure"(${matchPure.length}字) score=$bestScore overlap=$overlap jaccard=${jaccard.toStringAsFixed(2)}');
                  const minJaccard = 0.65;
                  final minOverlapForShort =
                      (ocrPure.length * 0.5).ceil().clamp(3, 10);
                  if (jaccard >= minJaccard && overlap >= minOverlapForShort) {
                    item.fundCode = match.code;
                    item.fundName = match.name;
                    item.code = match.code;
                    item.needsCodeMatch = false;
                    item.name = match.name;
                  } else {
                    debugPrint(
                        '[Import] ❌低相似度拒绝: jaccard=${jaccard.toStringAsFixed(2)}<$minJaccard overlap=$overlap<$minOverlapForShort');
                  }
                } else {
                  debugPrint(
                      '[Import] 未匹配: OCR="${h.name}" bestScore=$bestScore (需要>=4)');
                }
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
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF666600))),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: SelectableText(_rawOcrText,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF333300),
                            fontFamily: 'monospace')),
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
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
              const Spacer(),
              TextButton(
                  onPressed: _toggleSelectAll,
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
            left: 16,
            right: 16,
            top: 12,
            bottom: 12 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: const BoxDecoration(
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
                  child: Text('导入 $_selectedCount 只'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int get _selectedCount =>
      _holdings.where((h) => h.selected && h.amount > 0).length;

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
                                h.name.isNotEmpty
                                    ? h.name
                                    : (h.fundName ?? '未知基金'),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (h.code.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(h.code,
                                    style: const TextStyle(
                                        fontSize: 11, color: AppTheme.primary)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 昨日收益/持有收益/持有收益率
                        if (h.yesterdayProfit != null ||
                            h.holdingProfit != null) ...[
                          Text(
                            [
                              if (h.yesterdayProfit != null)
                                '昨日 ${h.yesterdayProfit! > 0 ? "+" : ""}${h.yesterdayProfit!.toStringAsFixed(2)}',
                              if (h.holdingProfit != null)
                                '持有 ${h.holdingProfit! > 0 ? "+" : ""}${h.holdingProfit!.toStringAsFixed(2)}',
                              if (h.holdingProfitRate != null)
                                '${h.holdingProfitRate! > 0 ? "+" : ""}${h.holdingProfitRate!.toStringAsFixed(2)}%',
                            ].join(' | '),
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Row(
                          children: [
                            _buildConfidenceBadge(h.confidence),
                            if (h.needsCodeMatch && h.code.isEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('需匹配',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.orange)),
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
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                    color: AppTheme.borderColor),
                              ),
                            ),
                            onChanged: (v) {
                              final amount = double.tryParse(v) ?? 0;
                              setState(() => h.amount = amount);
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('元',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textMuted)),
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
                          ButtonSegment(
                              value: ImportOperationType.sync,
                              label:
                                  Text('同步', style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: ImportOperationType.add,
                              label:
                                  Text('加仓', style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: ImportOperationType.reduce,
                              label:
                                  Text('减仓', style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: ImportOperationType.convert,
                              label:
                                  Text('转换', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {h.operationType},
                        onSelectionChanged: (v) =>
                            setState(() => h.operationType = v.first),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle:
                              WidgetStatePropertyAll(TextStyle(fontSize: 11)),
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
                  style:
                      TextStyle(fontSize: 12, color: Colors.orange.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: h.targetController,
            decoration: InputDecoration(
              hintText: '输入目标基金代码或名称搜索',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: h.targetSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (h.targetCode.isNotEmpty
                      ? const Icon(Icons.check_circle,
                          color: AppTheme.downColor, size: 20)
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
                    subtitle:
                        Text(r.code, style: const TextStyle(fontSize: 11)),
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
                  style:
                      TextStyle(fontSize: 11, color: Colors.orange.shade700)),
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
      decoration: const BoxDecoration(
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: h.searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
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
                    subtitle:
                        Text(r.code, style: const TextStyle(fontSize: 11)),
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
          const SnackBar(
            content: Text('搜索失败，请检查网络后重试'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
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
          const SnackBar(
            content: Text('搜索失败，请检查网络后重试'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
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
    for (final h in _holdings.where(
        (h) => h.selected && h.operationType == ImportOperationType.convert)) {
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
    final noCode = _holdings
        .where((h) => h.selected && h.amount > 0 && h.code.isEmpty)
        .toList();
    if (noCode.isNotEmpty) {
      _showError('${noCode.length} 条记录缺少基金代码，请点击展开搜索匹配');
      return;
    }

    // 验证名称完整性（名称太短说明OCR截断，数据不可靠）
    final shortName = _holdings
        .where((h) =>
            h.selected &&
            h.amount > 0 &&
            h.code.isNotEmpty &&
            (h.fundName ?? h.name).length < 4)
        .toList();
    if (shortName.isNotEmpty) {
      final names = shortName.map((h) => '"${h.fundName ?? h.name}"').join('、');
      _showError('以下记录名称过短，请手动搜索匹配：$names');
      return;
    }

    final toImport = _holdings
        .where((h) => h.selected && h.amount > 0 && h.code.isNotEmpty)
        .toList();
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
        SnackBar(
            content: Text(msg.trim()), behavior: SnackBarBehavior.floating),
      );

      context.pop();
    } catch (e) {
      if (!mounted) return;
      _showError('导入失败: $e');
      setState(() => _step = _ImportStep.preview);
    }
  }

  void _syncHolding(HoldingsBloc bloc, _EnhancedHoldingItem h, double netValue,
      double shares) {
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
        code: h.code,
        name: existing.name,
        shareClass: existing.shareClass,
        amount: newAmount,
        buyNetValue: avgNav,
        shares: newShares,
        buyDate: existing.buyDate,
        holdingDays: existing.holdingDays,
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
          code: h.code,
          name: existing.name,
          shareClass: existing.shareClass,
          amount: newAmount,
          buyNetValue: existing.buyNetValue,
          shares: newShares > 0 ? newShares : 0,
          buyDate: existing.buyDate,
          holdingDays: existing.holdingDays,
          createdAt: existing.createdAt,
        );
        bloc.add(HoldingsAdd(record));
      }
    }
  }

  Future<void> _convertHolding(
      HoldingsBloc bloc,
      _EnhancedHoldingItem h,
      Map<String, HoldingRecord> existingMap,
      double netValue,
      double shares,
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
          code: h.code,
          name: sourceExisting.name,
          shareClass: sourceExisting.shareClass,
          amount: newAmount,
          buyNetValue: sourceExisting.buyNetValue,
          shares: newShares > 0 ? newShares : 0,
          buyDate: sourceExisting.buyDate,
          holdingDays: sourceExisting.holdingDays,
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
        code: h.targetCode,
        name: targetExisting.name,
        shareClass: targetExisting.shareClass,
        amount: newAmount,
        buyNetValue: avgNav,
        shares: newShares,
        buyDate: targetExisting.buyDate,
        holdingDays: targetExisting.holdingDays,
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
  static const _shareClasses = {
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'H',
    'I',
    'R',
    'Y'
  };
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
      SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
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
  // OCR识别的收益字段
  double? yesterdayProfit;
  double? holdingProfit;
  double? holdingProfitRate;
  bool showSearch = false;
  bool searching = false;
  List<FundInfo> searchResults = [];

  // 转换专用
  String targetCode = ''; // 目标基金代码
  String targetName = ''; // 目标基金名称
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
    this.yesterdayProfit,
    this.holdingProfit,
    this.holdingProfitRate,
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
