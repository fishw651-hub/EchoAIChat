// 条件导入：Web 用 html 实现，其他平台用 io 实现
export 'platform_device_id_io.dart' if (dart.library.html) 'platform_device_id_web.dart';
