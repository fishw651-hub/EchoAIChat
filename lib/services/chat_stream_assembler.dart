/// 流式 tool_calls 增量拼装工具。
///
/// SSE 流中 `delta.tool_calls[]` 是分片到达的：首个分片携带 id/name，
/// 后续分片只携带 `function.arguments` 的字符串片段（按 `index` 归组）。
/// [ToolCallDeltaAssembler] 负责把分片累积成完整的 tool call。
///
/// [extractStreamingMessage] 则从**不完整**的 arguments JSON 字符串中
/// 渐进提取 `message` 字段的已收到部分，用于流式渲染可见文本。
library;

/// 单个流式 tool_call 分片。
class ToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? argumentsDelta;

  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });
}

/// 按 index 累积的一个 tool call 的当前快照。
class AssembledToolCall {
  final int index;
  String id = '';
  String name = '';
  final StringBuffer _arguments = StringBuffer();

  AssembledToolCall(this.index);

  /// 目前已累积的 arguments JSON 字符串（可能不完整）。
  String get arguments => _arguments.toString();
}

/// 按 index 累积 tool_calls 分片。
class ToolCallDeltaAssembler {
  final Map<int, AssembledToolCall> _calls = {};

  void add(ToolCallDelta delta) {
    final call = _calls.putIfAbsent(delta.index, () => AssembledToolCall(delta.index));
    if (delta.id != null && delta.id!.isNotEmpty) call.id = delta.id!;
    if (delta.name != null && delta.name!.isNotEmpty) call.name = delta.name!;
    if (delta.argumentsDelta != null) {
      call._arguments.write(delta.argumentsDelta);
    }
  }

  AssembledToolCall? callAt(int index) => _calls[index];

  /// 按 index 升序的全部 tool call 快照。
  List<AssembledToolCall> get calls {
    final list = _calls.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return list;
  }
}

/// 从不完整的 arguments JSON 中渐进提取 `"message"` 字符串值的已收到部分。
///
/// 处理的边界：
/// - arguments 尚未流到 `"message"` 键 → 返回空串
/// - 字符串未闭合（分片中途）→ 返回已解码部分
/// - 支持 `\"` `\\` `\/` `\n` `\t` `\r` `\b` `\f` `\uXXXX` 转义
/// - 末尾半截转义（如结尾是 `\` 或不完整的 `\u12`）暂不输出，等下个分片
String extractStreamingMessage(String partialArgs) {
  final keyMatch = RegExp('"message"\\s*:\\s*"').firstMatch(partialArgs);
  if (keyMatch == null) return '';

  final buf = StringBuffer();
  var i = keyMatch.end;
  while (i < partialArgs.length) {
    final ch = partialArgs[i];
    if (ch == '"') break; // 字符串闭合
    if (ch == '\\') {
      if (i + 1 >= partialArgs.length) break; // 末尾半截转义，等下个分片
      final esc = partialArgs[i + 1];
      switch (esc) {
        case '"':
          buf.write('"');
          i += 2;
        case '\\':
          buf.write('\\');
          i += 2;
        case '/':
          buf.write('/');
          i += 2;
        case 'n':
          buf.write('\n');
          i += 2;
        case 't':
          buf.write('\t');
          i += 2;
        case 'r':
          buf.write('\r');
          i += 2;
        case 'b':
          buf.write('\b');
          i += 2;
        case 'f':
          buf.write('\f');
          i += 2;
        case 'u':
          // 不完整的 \uXXXX 只可能出现在末尾：暂不输出，等下个分片
          if (i + 6 > partialArgs.length) return buf.toString();
          final hex = partialArgs.substring(i + 2, i + 6);
          final code = int.tryParse(hex, radix: 16);
          if (code == null) {
            // 容错：非法 hex，丢弃反斜杠继续
            i += 1;
            continue;
          }
          buf.write(String.fromCharCode(code));
          i += 6;
        default:
          // 未知转义：原样输出字符
          buf.write(esc);
          i += 2;
      }
      continue;
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}
