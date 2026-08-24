class ChatToolArguments {
  final String message;
  final String? stickerId;

  const ChatToolArguments({this.message = '', this.stickerId});

  @override
  bool operator ==(Object other) =>
      other is ChatToolArguments &&
      other.message == message &&
      other.stickerId == stickerId;

  @override
  int get hashCode => Object.hash(message, stickerId);
}

class StickerMessageCodec {
  static String composeContent(String message, String? description) {
    final text = message.trim();
    final sticker = description?.trim() ?? '';
    if (sticker.isEmpty) return text;
    if (text.isEmpty) return '[表情]$sticker';
    return '$text\n[表情]$sticker';
  }

  static ChatToolArguments parseChatArguments(Map<String, dynamic> arguments) {
    final rawMessage = arguments['message'];
    final rawStickerId = arguments['sticker_id'];
    return ChatToolArguments(
      message: rawMessage is String ? rawMessage.trim() : '',
      stickerId: rawStickerId is String && rawStickerId.trim().isNotEmpty
          ? rawStickerId.trim()
          : null,
    );
  }

  static Map<String, dynamic> buildChatTool({
    required List<Map<String, String>> stickers,
  }) {
    final stickerDescription = stickers.isEmpty
        ? '当前没有可用表情。'
        : stickers
            .map((item) => '${item['id']}: ${item['description']}')
            .join('\n');
    return {
      'type': 'function',
      'function': {
        'name': 'chat',
        'description': '发送最终自然语言回复，可同时发送最多一个表情。表情清单：\n$stickerDescription',
        'parameters': {
          'type': 'object',
          'properties': {
            'message': {'type': 'string', 'description': '回复文字；只发表情时可以为空'},
            'sticker_id': {'type': 'string', 'description': '可选，只能从上方清单选择一个 ID'},
          },
          'required': <String>[],
        },
      },
    };
  }
}
