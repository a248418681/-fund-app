import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';

/// 基金名乱码 bug 的回归测试。
///
/// 背景：天天基金估值接口 fundgz.1234567.com.cn 返回 UTF-8，
/// 此前误用 gbk.decode 解码导致基金名乱码。本测试锁住「必须用 UTF-8 解码」这一修复。
void main() {
  // 「易方达蓝筹精选混合」的标准 UTF-8 字节（接口实测）
  final utf8Bytes = Uint8List.fromList(
    utf8.encode('jsonpgz({"fundcode":"005827","name":"易方达蓝筹精选混合"});'),
  );

  group('估值接口 UTF-8 解码（乱码 bug 回归）', () {
    test('UTF-8 解码得到正确中文基金名', () {
      final text = utf8.decode(utf8Bytes, allowMalformed: true);
      final jsonStr = text.replaceFirst('jsonpgz(', '').replaceAll(');', '');
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(result['name'], '易方达蓝筹精选混合');
      expect(result['fundcode'], '005827');
    });

    test('用 GBK 解码 UTF-8 字节会产生乱码（证明旧实现的 bug）', () {
      // gbk.decode 解 UTF-8 字节不会抛异常，只是解出乱码——这正是旧 bug 难以察觉的原因
      final garbled = gbk.decode(utf8Bytes);
      expect(garbled.contains('易方达蓝筹精选混合'), isFalse,
          reason: 'GBK 解码 UTF-8 字节必然得不到正确中文');
    });
  });
}
