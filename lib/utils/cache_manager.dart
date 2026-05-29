/// 带 TTL 的泛型缓存管理器
class CacheManager<T> {
  final int ttlMs;
  final Map<String, _CacheEntry<T>> _store = {};

  CacheManager(this.ttlMs);

  /// 获取缓存值（过期返回 null）
  T? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired(ttlMs)) {
      _store.remove(key);
      return null;
    }
    return entry.data;
  }

  /// 存入缓存
  void set(String key, T value) {
    _store[key] = _CacheEntry(value);
  }

  /// 清空所有缓存
  void clear() => _store.clear();

  /// 清理过期条目
  void cleanExpired() {
    _store.removeWhere((_, entry) => entry.isExpired(ttlMs));
  }

  /// 检查是否有有效缓存
  bool containsKey(String key) {
    final entry = _store[key];
    return entry != null && !entry.isExpired(ttlMs);
  }
}

/// 缓存条目（带时间戳）
class _CacheEntry<T> {
  final T data;
  final int timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now().millisecondsSinceEpoch;

  bool isExpired(int ttlMs) =>
      DateTime.now().millisecondsSinceEpoch - timestamp > ttlMs;
}
