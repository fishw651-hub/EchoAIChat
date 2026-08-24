import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/services/sticker_message_codec.dart';

void main() {
  test('composes actual sticker description into chat content', () {
    expect(
      StickerMessageCodec.composeContent('今天真不错', '开心'),
      '今天真不错\n[表情]开心',
    );
    expect(StickerMessageCodec.composeContent('', '委屈巴巴'), '[表情]委屈巴巴');
  });

  test('ignores empty sticker descriptions', () {
    expect(StickerMessageCodec.composeContent('你好', '  '), '你好');
  });

  test('parses one optional sticker id from chat arguments', () {
    expect(
      StickerMessageCodec.parseChatArguments({
        'message': '你好',
        'sticker_id': 'sticker-1',
      }),
      const ChatToolArguments(message: '你好', stickerId: 'sticker-1'),
    );
    expect(
      StickerMessageCodec.parseChatArguments({'message': '你好'}),
      const ChatToolArguments(message: '你好'),
    );
  });

  test('builds a private chat tool with the available sticker list', () {
    final tool = StickerMessageCodec.buildChatTool(
      stickers: const [
        {'id': 'sticker-1', 'description': '开心'},
      ],
    );
    expect(tool['function']['name'], 'chat');
    expect(tool['function']['description'], contains('sticker-1: 开心'));
    expect(tool['function']['parameters']['properties']['sticker_id'], isNotNull);
  });
}
