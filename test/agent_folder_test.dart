import 'package:aichat/models/agent.dart';
import 'package:aichat/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('agent-folder');
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('agent_folder_members');
    await db.delete('agent_folders');
    await db.delete('agents');
  });

  Future<Agent> insertAgent(String name) async {
    final agent = Agent(name: name, persona: '测试人设');
    await DatabaseService.insertAgent(agent);
    return agent;
  }

  test('编组 CRUD：创建、重命名、查成员、成员数、解散', () async {
    final a1 = await insertAgent('小诗');
    final a2 = await insertAgent('阿澈');

    final folderId = await DatabaseService.createAgentFolder('室友组');
    await DatabaseService.addAgentsToFolder(folderId, [a1.id, a2.id]);

    var folders = await DatabaseService.getAgentFolders();
    expect(folders.length, 1);
    expect(folders.first['name'], '室友组');
    expect(folders.first['member_count'], 2);

    final memberIds = await DatabaseService.getFolderMemberAgentIds(folderId);
    expect(memberIds, unorderedEquals([a1.id, a2.id]));

    await DatabaseService.renameAgentFolder(folderId, '新名字');
    folders = await DatabaseService.getAgentFolders();
    expect(folders.first['name'], '新名字');

    await DatabaseService.deleteAgentFolder(folderId);
    folders = await DatabaseService.getAgentFolders();
    expect(folders, isEmpty);
    expect(await DatabaseService.getFolderMemberAgentIds(folderId), isEmpty);
  });

  test('一个智能体只能属于一个编组：加入新编组会移除旧映射', () async {
    final a1 = await insertAgent('小诗');

    final folder1 = await DatabaseService.createAgentFolder('编组一');
    final folder2 = await DatabaseService.createAgentFolder('编组二');

    await DatabaseService.addAgentsToFolder(folder1, [a1.id]);
    await DatabaseService.addAgentsToFolder(folder2, [a1.id]);

    expect(await DatabaseService.getFolderMemberAgentIds(folder1), isEmpty);
    expect(await DatabaseService.getFolderMemberAgentIds(folder2), [a1.id]);

    final memberships = await DatabaseService.getAgentFolderMemberships();
    expect(memberships[a1.id], folder2);
  });

  test('移出编组', () async {
    final a1 = await insertAgent('小诗');
    final folderId = await DatabaseService.createAgentFolder('编组');
    await DatabaseService.addAgentsToFolder(folderId, [a1.id]);

    await DatabaseService.removeAgentsFromFolder([a1.id]);
    expect(await DatabaseService.getFolderMemberAgentIds(folderId), isEmpty);
    expect(await DatabaseService.getAgentFolderMemberships(), isEmpty);
  });

  test('解散编组不删除智能体', () async {
    final a1 = await insertAgent('小诗');
    final folderId = await DatabaseService.createAgentFolder('编组');
    await DatabaseService.addAgentsToFolder(folderId, [a1.id]);

    await DatabaseService.deleteAgentFolder(folderId);

    final agents = await DatabaseService.getAgents();
    expect(agents.map((a) => a.id), contains(a1.id));
  });
}
