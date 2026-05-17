import re

path = "E:/Qbot/fund-app-new/lib/data/datasources/remote/fund_remote_datasource.dart"
with open(path, encoding="utf-8") as f:
    c = f.read()

# Fix 1: Add transformResponse to Dio to bypass FusedTransformer content-type check
old_dio = """FundRemoteDataSource() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 Chrome/88.0.4324.181 Mobile Safari/537.36',
      'Referer': 'https://fund.eastmoney.com/',
    },
  ));"""

new_dio = """FundRemoteDataSource() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 Chrome/88.0.4324.181 Mobile Safari/537.36',
      'Referer': 'https://fund.eastmoney.com/',
    },
  )) {
  // 禁用默认 transformer，避免 content-type 验证失败
  _dio.transformer = _NoopTransformer();
}"""

if old_dio in c:
    c = c.replace(old_dio, new_dio)
    print("Fixed Dio transformer")
else:
    print("old_dio NOT found")
    # print around Dio(
    idx = c.find("FundRemoteDataSource() : _dio = Dio(")
    print(repr(c[idx:idx+500]))

with open(path, "w", encoding="utf-8") as f:
    f.write(c)
