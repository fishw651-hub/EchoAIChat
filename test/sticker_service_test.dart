import 'package:flutter_test/flutter_test.dart';

import 'package:aichat/services/database_service.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('sticker-service');
  });

  tearDownAll(() => testDatabase.close());

  test('stores active stickers and local message snapshots', () async {
    final database = await DatabaseService.database;
    await database.delete('stickers');
    await database.delete('local_sticker_messages');

    final stickerId = await DatabaseService.insertSticker(
      id: 'sticker-test',
      description: '开心',
      imagePath: 'sticker_assets/test.png',
      createdAt: 1,
      updatedAt: 1,
    );
    expect(stickerId, 'sticker-test');

    final stickers = await DatabaseService.getStickers();
    expect(stickers.single['description'], '开心');

    final messageId = await DatabaseService.insertChatMessage(
      role: 'user',
      content: '[表情]开心',
      timestampMs: 1,
      agentId: 'agent-test',
    );
    await DatabaseService.insertStickerMessageSnapshot(
      chatMessageId: messageId,
      stickerId: stickerId,
      description: '开心',
      imagePath: 'sticker_assets/test.png',
      createdAt: 1,
    );
    final snapshot = await DatabaseService.getStickerMessageSnapshot(messageId);
    expect(snapshot?['description_snapshot'], '开心');
  });
}
