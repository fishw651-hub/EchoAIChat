import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Web 端数据库工厂初始化
/// 在 main() 中调用一次，将 sqflite 工厂切换到 ffi_web
///
/// 使用 noWebWorker 模式：在主线程直接加载 sqlite3.wasm，不走 worker。
/// 优点：
///   - 不需要 sqflite_sw.js worker 脚本，减少一个加载失败点
///   - 路径解析更简单，只需确保 /web/sqlite3.wasm 可访问
///   - 兼容性更好（SharedWorker 在部分移动浏览器不支持）
/// 缺点：
///   - 数据库操作在主线程执行，极少量数据时 UI 不受影响
Future<void> initWebDatabase() async {
  sqfliteFfiInit();
  // noWebWorker 模式：主线程直接加载 wasm，不走 worker
  // 只需要 /web/sqlite3.wasm 可访问即可
  databaseFactory = createDatabaseFactoryFfiWeb(
    noWebWorker: true,
    options: SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('/web/sqlite3.wasm'),
    ),
  );
  debugPrint('[Web] databaseFactory set to ffi_web (noWebWorker mode)');
}
