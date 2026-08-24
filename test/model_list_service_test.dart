import 'dart:convert';

import 'package:aichat/services/model_list_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelListService.parse', () {
    test('解析完整字段（含 thinking_status）', () {
      final body = jsonEncode({
        'code': 0,
        'data': [
          {
            'id': 'deepseek-v4-flash',
            'name': 'DeepSeek V4 Flash',
            'cache_price': 0.1,
            'input_price': 1.0,
            'output_price': 2.0,
            'thinking_status': 1,
          },
          {
            'id': 'deepseek-v4-lite',
            'name': 'DeepSeek V4 Lite',
            'thinking_status': 0,
          },
        ],
      });

      final models = ModelListService.parse(body);

      expect(models, hasLength(2));
      expect(models[0].id, 'deepseek-v4-flash');
      expect(models[0].name, 'DeepSeek V4 Flash');
      expect(models[0].thinkingStatus, 1);
      expect(models[1].thinkingStatus, 0);
    });

    test('解析服务器实际形态（data 为 {models: [...]} 对象）', () {
      final body = jsonEncode({
        'code': 0,
        'message': 'success',
        'data': {
          'models': [
            {
              'id': 'grok-4.3',
              'name': 'grok-4.3',
              'input_price_per_1m': 1.3,
              'thinking_status': 1,
            },
          ],
        },
      });

      final models = ModelListService.parse(body);

      expect(models.single.id, 'grok-4.3');
      expect(models.single.thinkingStatus, 1);
    });

    test('thinking_status 缺失时默认 1', () {
      final body = jsonEncode({
        'code': 0,
        'data': [
          {'id': 'deepseek-v4-flash', 'name': 'Flash'},
        ],
      });

      final models = ModelListService.parse(body);

      expect(models.single.thinkingStatus, 1);
    });

    test('name 缺失时回退为 id', () {
      final body = jsonEncode({
        'code': 0,
        'data': [
          {'id': 'deepseek-v4-flash'},
        ],
      });

      final models = ModelListService.parse(body);

      expect(models.single.name, 'deepseek-v4-flash');
    });

    test('跳过空 id 条目', () {
      final body = jsonEncode({
        'code': 0,
        'data': [
          {'id': '', 'name': 'invalid'},
          {'name': 'no-id'},
          {'id': 'deepseek-v4-flash', 'name': 'Flash'},
        ],
      });

      final models = ModelListService.parse(body);

      expect(models, hasLength(1));
      expect(models.single.id, 'deepseek-v4-flash');
    });

    test('code != 0 时抛 FormatException', () {
      final body = jsonEncode({'code': 500, 'message': 'server error'});

      expect(() => ModelListService.parse(body), throwsFormatException);
    });

    test('data 缺失或为空列表时抛 FormatException', () {
      expect(
        () => ModelListService.parse(jsonEncode({'code': 0})),
        throwsFormatException,
      );
      expect(
        () => ModelListService.parse(jsonEncode({'code': 0, 'data': []})),
        throwsFormatException,
      );
    });
  });

  group('ModelListService 缓存', () {
    test('saveCache / loadCached 往返', () async {
      SharedPreferences.setMockInitialValues({});
      const models = [
        ModelInfo(id: 'a', name: 'A', thinkingStatus: 0),
        ModelInfo(id: 'b', name: 'B'),
      ];

      await ModelListService.saveCache(models);
      final loaded = await ModelListService.loadCached();

      expect(loaded, hasLength(2));
      expect(loaded[0].id, 'a');
      expect(loaded[0].thinkingStatus, 0);
      expect(loaded[1].thinkingStatus, 1);
    });

    test('无缓存或缓存损坏时返回空列表', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ModelListService.loadCached(), isEmpty);

      SharedPreferences.setMockInitialValues({'cached_model_list': 'not-json'});
      expect(await ModelListService.loadCached(), isEmpty);
    });
  });

  group('ModelListService.fetch', () {
    tearDown(() {
      ModelListService.testClient = null;
    });

    test('成功时返回解析后的模型列表', () async {
      ModelListService.testClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              {'id': 'deepseek-v4-flash', 'name': 'Flash'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final models = await ModelListService.instance.fetch();

      expect(models.single.id, 'deepseek-v4-flash');
    });

    test('非 200 响应抛出异常', () async {
      ModelListService.testClient = MockClient(
        (request) async => http.Response('oops', 500),
      );

      expect(ModelListService.instance.fetch(), throwsA(anything));
    });
  });

  group('ModelListService.supportsThinking', () {
    const models = [
      ModelInfo(id: 'a', name: 'A', thinkingStatus: 0),
      ModelInfo(id: 'b', name: 'B', thinkingStatus: 1),
    ];

    test('thinking_status==0 返回 false，==1 返回 true', () {
      expect(ModelListService.supportsThinking(models, 'a'), isFalse);
      expect(ModelListService.supportsThinking(models, 'b'), isTrue);
    });

    test('未知模型不降级（fail-open）', () {
      expect(ModelListService.supportsThinking(models, 'unknown'), isTrue);
      expect(ModelListService.supportsThinking(const [], 'a'), isTrue);
    });
  });

  group('ModelListService.canSendImages（发图能力预检）', () {
    test('查不到模型（列表未就绪/刷新失败）fail-open 放行', () {
      expect(ModelListService.canSendImages(null), isTrue);
    });

    test('明确查到不能识图才拦截', () {
      const plain = ModelInfo(id: 'plain', name: 'Plain');
      expect(plain.canSeeImages, isFalse);
      expect(ModelListService.canSendImages(plain), isFalse);
    });

    test('原生视觉或绑定视觉模型放行', () {
      const native = ModelInfo(id: 'n', name: 'N', nativeVision: true);
      const bound = ModelInfo(id: 'b', name: 'B', visionModelId: 'vl');
      expect(ModelListService.canSendImages(native), isTrue);
      expect(ModelListService.canSendImages(bound), isTrue);
    });
  });

  group('ModelInfo 视觉字段', () {
    test('解析 native_vision / vision_model_id', () {
      final body = jsonEncode({
        'code': 0,
        'data': [
          {
            'id': 'vision-native',
            'name': 'Native',
            'native_vision': true,
            'vision_model_id': '',
          },
          {
            'id': 'vision-bound',
            'name': 'Bound',
            'native_vision': false,
            'vision_model_id': 'deepseek-vl2',
          },
        ],
      });

      final models = ModelListService.parse(body);

      expect(models[0].nativeVision, isTrue);
      expect(models[0].visionModelId, isEmpty);
      expect(models[0].canSeeImages, isTrue);
      expect(models[1].nativeVision, isFalse);
      expect(models[1].visionModelId, 'deepseek-vl2');
      expect(models[1].canSeeImages, isTrue);
    });

    test('字段缺失时默认 false / 空串（旧版服务器兼容）', () {
      final body = jsonEncode({
        'code': 0,
        'data': [
          {'id': 'plain', 'name': 'Plain'},
        ],
      });

      final model = ModelListService.parse(body).single;

      expect(model.nativeVision, isFalse);
      expect(model.visionModelId, isEmpty);
      expect(model.canSeeImages, isFalse);
    });

    test('toJson/fromJson 往返保留视觉字段', () {
      const model = ModelInfo(
        id: 'm',
        name: 'M',
        thinkingStatus: 0,
        nativeVision: true,
        visionModelId: 'vl-model',
      );

      final restored = ModelInfo.fromJson(model.toJson());

      expect(restored.nativeVision, isTrue);
      expect(restored.visionModelId, 'vl-model');
      expect(restored.thinkingStatus, 0);
    });

    test('findById 命中与未命中', () {
      const models = [
        ModelInfo(id: 'a', name: 'A'),
        ModelInfo(id: 'b', name: 'B', nativeVision: true),
      ];

      expect(ModelListService.findById(models, 'b')?.nativeVision, isTrue);
      expect(ModelListService.findById(models, 'missing'), isNull);
    });
  });

  group('ModelListNotifier', () {
    test('初始加载缓存列表', () async {
      SharedPreferences.setMockInitialValues({
        'cached_model_list': jsonEncode([
          {'id': 'cached-model', 'name': 'Cached', 'thinking_status': 0},
        ]),
      });

      final notifier = ModelListNotifier();
      expect(notifier.state.models.single.id, ModelListService.defaultModel);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.models.single.id, 'cached-model');
    });

    test('refresh 成功更新状态并写缓存，失败保留现状', () async {
      SharedPreferences.setMockInitialValues({});
      ModelListService.testClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              {'id': 'fresh-model', 'name': 'Fresh', 'thinking_status': 1},
            ],
          }),
          200,
        );
      });
      addTearDown(() {
        ModelListService.testClient = null;
      });

      final notifier = ModelListNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final error = await notifier.refresh();
      expect(error, isNull);
      expect(notifier.state.models.single.id, 'fresh-model');
      expect(notifier.state.refreshing, isFalse);
      final cached = await ModelListService.loadCached();
      expect(cached.single.id, 'fresh-model');

      // 失败时返回错误描述并保留现有列表
      ModelListService.testClient = MockClient(
        (request) async => http.Response('oops', 500),
      );
      final failure = await notifier.refresh();
      expect(failure, isNotNull);
      expect(notifier.state.models.single.id, 'fresh-model');
      expect(notifier.state.refreshing, isFalse);
    });
  });
}
