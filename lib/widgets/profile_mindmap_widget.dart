import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/profile_ai_service.dart';
import '../services/chat_runtime_policy.dart';
import '../screens/profile_init_wizard_screen.dart';
import '../theme/app_theme.dart';
import 'echo_visual_surface.dart';
import 'profile_mindmap_controls.dart';

class ProfileMindMapWidget extends ConsumerStatefulWidget {
  const ProfileMindMapWidget({super.key});

  @override
  ConsumerState<ProfileMindMapWidget> createState() =>
      _ProfileMindMapWidgetState();
}

class _ProfileMindMapWidgetState extends ConsumerState<ProfileMindMapWidget> {
  final Set<String> _collapsedCategories = {};
  final Map<String, bool> _generatingQuestions = {}; // category -> loading
  final TransformationController _transformationController =
      TransformationController();
  bool _viewInitialized = false;
  Size? _lastViewportSize;

  // 画布与布局常量
  static const double _canvasSize = 1200.0;
  static const Offset _center = Offset(_canvasSize / 2, _canvasSize / 2);
  static const double _categoryRadius = 220.0;
  // 叶子节点沿径向延伸的间距
  static const double _leafBaseOffset = 110.0; // 距分类节点的起始偏移
  static const double _leafSpacing = 95.0; // 相邻叶子之间的径向间距

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _initViewTransform(Size viewportSize, {bool force = false}) {
    if (!force && _viewInitialized && _lastViewportSize == viewportSize) return;
    _viewInitialized = true;
    _lastViewportSize = viewportSize;
    final scale = ProfileMindMapViewport.initialScale(viewportSize);
    final dx = viewportSize.width / 2 - (_canvasSize / 2) * scale;
    final dy = viewportSize.height / 2 - (_canvasSize / 2) * scale;
    _transformationController.value = Matrix4(
      scale,
      0,
      0,
      0,
      0,
      scale,
      0,
      0,
      0,
      0,
      1,
      0,
      dx,
      dy,
      0,
      1,
    );
  }

  void _zoomBy(double factor) {
    final viewportSize = _lastViewportSize;
    if (viewportSize == null) return;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.3, 2.5).toDouble();
    final viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    final sceneCenter = _transformationController.toScene(viewportCenter);
    final dx = viewportCenter.dx - sceneCenter.dx * targetScale;
    final dy = viewportCenter.dy - sceneCenter.dy * targetScale;
    _transformationController.value = Matrix4(
      targetScale,
      0,
      0,
      0,
      0,
      targetScale,
      0,
      0,
      0,
      0,
      1,
      0,
      dx,
      dy,
      0,
      1,
    );
  }

  void _resetView() {
    final viewportSize = _lastViewportSize;
    if (viewportSize != null) {
      _initViewTransform(viewportSize, force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userProfileProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final totalCount = state.totalCount;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.totalCount == 0) {
      return _buildEmptyState(context, ref, l10n, scheme);
    }

    final categories = state.grouped.entries.toList()
      ..sort(
        (a, b) => ProfileEntry.validCategories
            .indexOf(a.key)
            .compareTo(ProfileEntry.validCategories.indexOf(b.key)),
      );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            AppTheme.space4,
            AppTheme.space4,
            0,
          ),
          child: EchoProfileHeader(
            totalCount: totalCount,
            onEdit: () => _showCenterMenu(context, ref),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4,
            vertical: AppTheme.space2,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppTheme.space2,
              runSpacing: AppTheme.space1,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(l10n.get('addProfileItem')),
                  onPressed: () => _showCreateDialog(context, ref),
                ),
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(l10n.get('startBuildingProfile')),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileInitWizardScreen(),
                      ),
                    );
                  },
                ),
                if (state.totalCount > 0)
                  ActionChip(
                    avatar: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: scheme.error,
                    ),
                    label: Text(
                      l10n.get('clearAll'),
                      style: TextStyle(color: scheme.error),
                    ),
                    onPressed: () => _confirmClearAll(context, ref),
                  ),
              ],
            ),
          ),
        ),
        // 思维导图
        Expanded(
          child: _buildMindMap(
            context,
            ref,
            categories,
            state.totalCount,
            scheme,
            l10n,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 64,
              color: scheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('noProfileData'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('noProfileDataDesc'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileInitWizardScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.get('startBuildingProfile')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMindMap(
    BuildContext context,
    WidgetRef ref,
    List<MapEntry<String, List<ProfileEntry>>> categories,
    int totalCount,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final visibleCategories = categories
        .where((e) => e.value.isNotEmpty)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 首次布局时设置居中变换
        _initViewTransform(Size(constraints.maxWidth, constraints.maxHeight));

        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: false,
                  minScale: 0.3,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(200),
                  child: SizedBox(
                    width: _canvasSize,
                    height: _canvasSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 连线层
                        CustomPaint(
                          size: const Size(_canvasSize, _canvasSize),
                          painter: _MindMapPainter(
                            center: _center,
                            categories: visibleCategories,
                            categoryRadius: _categoryRadius,
                            leafBaseOffset: _leafBaseOffset,
                            leafSpacing: _leafSpacing,
                            collapsed: _collapsedCategories,
                            lineColor: scheme.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        // 中心节点
                        Positioned(
                          left: _center.dx - 60,
                          top: _center.dy - 60,
                          child: GestureDetector(
                            onTap: () => _showCenterMenu(context, ref),
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.primaryContainer,
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.psychology_alt_outlined,
                                    size: 32,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.get('userProfileTitle'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  Text(
                                    '$totalCount',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onPrimaryContainer
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 分类节点 + 叶子节点
                        ..._buildCategoryAndLeaves(
                          context,
                          ref,
                          visibleCategories,
                          scheme,
                          l10n,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: AppTheme.space3,
              bottom: AppTheme.space3,
              child: ProfileMindMapControls(
                onZoomIn: () => _zoomBy(1.2),
                onZoomOut: () => _zoomBy(1 / 1.2),
                onReset: _resetView,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建分类节点和叶子节点。叶子节点沿径向（从中心向分类节点方向）延伸，
  /// 避免相邻分类的叶子相互重叠。
  List<Widget> _buildCategoryAndLeaves(
    BuildContext context,
    WidgetRef ref,
    List<MapEntry<String, List<ProfileEntry>>> categories,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final widgets = <Widget>[];
    final n = categories.length;
    if (n == 0) return widgets;

    for (int i = 0; i < n; i++) {
      final entry = categories[i];
      final category = entry.key;
      final profiles = entry.value;
      // 等角度分布，从正上方开始
      final angle = (2 * math.pi * i / n) - math.pi / 2;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final catPos = Offset(
        _center.dx + _categoryRadius * cosA,
        _center.dy + _categoryRadius * sinA,
      );

      // 分类节点
      widgets.add(
        Positioned(
          left: catPos.dx - 76,
          top: catPos.dy - 28,
          child: _CategoryNode(
            category: category,
            count: profiles.length,
            isCollapsed: _collapsedCategories.contains(category),
            isLoading: _generatingQuestions[category] == true,
            onTap: () {
              setState(() {
                if (_collapsedCategories.contains(category)) {
                  _collapsedCategories.remove(category);
                } else {
                  _collapsedCategories.add(category);
                }
              });
            },
            onSupplement: () =>
                _triggerCategoryQuestionnaire(context, ref, category, profiles),
          ),
        ),
      );

      // 叶子节点（若未收起）—— 沿径向延伸
      if (!_collapsedCategories.contains(category)) {
        final visibleLeafCount = math.min(profiles.length, 3);
        for (int j = 0; j < visibleLeafCount; j++) {
          final p = profiles[j];
          // 距中心的径向距离：分类节点半径 + 起始偏移 + j * 间距
          final leafDist = _categoryRadius + _leafBaseOffset + j * _leafSpacing;
          final leafPos = Offset(
            _center.dx + leafDist * cosA,
            _center.dy + leafDist * sinA,
          );
          widgets.add(
            Positioned(
              left: leafPos.dx - 90,
              top: leafPos.dy - 42,
              child: _LeafNode(
                entry: p,
                onEdit: () => _showEditDialog(context, ref, p),
                onDelete: () =>
                    ref.read(userProfileProvider.notifier).deleteProfile(p.id),
              ),
            ),
          );
        }
        if (profiles.length > 3) {
          final moreDist = _categoryRadius + _leafBaseOffset + 3 * _leafSpacing;
          final morePos = Offset(
            _center.dx + moreDist * cosA,
            _center.dy + moreDist * sinA,
          );
          widgets.add(
            Positioned(
              left: morePos.dx - 55,
              top: morePos.dy - 20,
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: AppTheme.brMd,
                child: InkWell(
                  borderRadius: AppTheme.brMd,
                  onTap: () =>
                      _showCategoryEntries(context, ref, category, profiles),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space3,
                      vertical: AppTheme.space2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.brMd,
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      '还有 ${profiles.length - 3} 条',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    return widgets;
  }

  Future<void> _showCategoryEntries(
    BuildContext context,
    WidgetRef ref,
    String category,
    List<ProfileEntry> profiles,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final label = ProfileEntry.categoryLabels[category] ?? category;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space4,
                  AppTheme.space2,
                  AppTheme.space4,
                  AppTheme.space3,
                ),
                child: EchoSectionHeader(
                  title: label,
                  subtitle: '共 ${profiles.length} 条观察，点击可编辑',
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppTheme.space6),
                  itemCount: profiles.length,
                  separatorBuilder: (_, _) => const Divider(indent: 76),
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final updated = profile.updatedAt;
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.7),
                          borderRadius: AppTheme.brMd,
                        ),
                        child: Text(
                          '${profile.confidence}%',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      title: Text(profile.key),
                      subtitle: Text(
                        '${profile.value}\n${profileSourceLabel(profile.source)}'
                        ' · 更新于 ${updated.month}/${updated.day}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showEditDialog(context, ref, profile);
                      },
                      trailing: IconButton(
                        tooltip: '删除${profile.key}',
                        onPressed: () async {
                          await ref
                              .read(userProfileProvider.notifier)
                              .deleteProfile(profile.id);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _triggerCategoryQuestionnaire(
    BuildContext context,
    WidgetRef ref,
    String category,
    List<ProfileEntry> existing,
  ) async {
    final auth = ref.read(authProvider);
    setState(() => _generatingQuestions[category] = true);
    try {
      final questions = await ProfileAiService.generateQuestionsForCategory(
        category: category,
        existingEntries: existing,
        apiKey: auth.apiKey ?? '',
        baseUrl: '', // 由 ApiService 内部用 ServerConfig
        temperature: ChatRuntimePolicy.qualityTask.temperature ?? 1.3,
      );
      if (!mounted) return;
      await showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (_) => _CategoryQuestionDialog(
          category: category,
          questions: questions,
          onSave: ref.read(userProfileProvider.notifier).createProfiles,
        ),
      );
    } catch (e) {
      debugPrint('[MindMap] supplement questionnaire failed: $e');
    } finally {
      if (mounted) setState(() => _generatingQuestions[category] = false);
    }
  }

  void _showCenterMenu(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.get('addProfileItem')),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(l10n.get('startBuildingProfile')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileInitWizardScreen(),
                  ),
                );
              },
            ),
            if (ref.read(userProfileProvider).totalCount > 0)
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.get('clearAll'),
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmClearAll(context, ref);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final keyCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    String selectedCategory = 'basic_info';
    final confidenceNotifier = ValueNotifier<double>(80);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.get('addProfileItem')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: InputDecoration(
                    labelText: l10n.get('profileCategory'),
                  ),
                  items: ProfileEntry.validCategories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            '${ProfileEntry.categoryIcons[c] ?? "📌"} ${ProfileEntry.categoryLabels[c] ?? c}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => selectedCategory = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.get('profileKey'),
                    hintText: '例如：姓名、年龄、爱好',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.get('profileValue'),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      l10n.get('confidenceLabel'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueListenableBuilder<double>(
                        valueListenable: confidenceNotifier,
                        builder: (_, v, child) => Slider(
                          value: v,
                          min: 0,
                          max: 100,
                          divisions: 10,
                          label: '${v.round()}%',
                          onChanged: (v) => confidenceNotifier.value = v,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: confidenceNotifier,
                      builder: (_, v, child) => Text(
                        '${v.round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (keyCtrl.text.trim().isNotEmpty &&
                    valueCtrl.text.trim().isNotEmpty) {
                  ref
                      .read(userProfileProvider.notifier)
                      .createProfile(
                        category: selectedCategory,
                        key: keyCtrl.text.trim(),
                        value: valueCtrl.text.trim(),
                        confidence: confidenceNotifier.value.round(),
                        source: 'manual',
                      );
                  Navigator.pop(ctx);
                }
              },
              child: Text(l10n.get('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    ProfileEntry profile,
  ) {
    final l10n = AppLocalizations.of(context);
    final valueCtrl = TextEditingController(text: profile.value);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${profile.categoryIcon} ${profile.key}'),
        content: TextField(
          controller: valueCtrl,
          decoration: InputDecoration(labelText: l10n.get('profileValue')),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (valueCtrl.text.trim().isNotEmpty) {
                ref
                    .read(userProfileProvider.notifier)
                    .updateProfile(
                      profile.copyWith(
                        value: valueCtrl.text.trim(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmClearAllTitle')),
        content: Text(l10n.get('confirmClearAllContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () {
              ref.read(userProfileProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('confirmClearAction')),
          ),
        ],
      ),
    );
  }
}

/// 思维导图连线 painter
class _MindMapPainter extends CustomPainter {
  final Offset center;
  final List<MapEntry<String, List<ProfileEntry>>> categories;
  final double categoryRadius;
  final double leafBaseOffset;
  final double leafSpacing;
  final Set<String> collapsed;
  final Color lineColor;

  _MindMapPainter({
    required this.center,
    required this.categories,
    required this.categoryRadius,
    required this.leafBaseOffset,
    required this.leafSpacing,
    required this.collapsed,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final n = categories.length;
    if (n == 0) return;

    for (int i = 0; i < n; i++) {
      final entry = categories[i];
      final angle = (2 * math.pi * i / n) - math.pi / 2;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final catPos = Offset(
        center.dx + categoryRadius * cosA,
        center.dy + categoryRadius * sinA,
      );
      // 中心 → 分类节点
      _drawBezier(canvas, paint, center, catPos);

      if (!collapsed.contains(entry.key)) {
        final leaves = entry.value;
        final visibleLeafCount = math.min(leaves.length, 3);
        for (int j = 0; j < visibleLeafCount; j++) {
          // 沿径向延伸
          final leafDist = categoryRadius + leafBaseOffset + j * leafSpacing;
          final leafPos = Offset(
            center.dx + leafDist * cosA,
            center.dy + leafDist * sinA,
          );
          _drawBezier(canvas, paint, catPos, leafPos);
        }
      }
    }
  }

  void _drawBezier(Canvas canvas, Paint paint, Offset from, Offset to) {
    // 径向连线：用与径向方向一致的轻微弯曲贝塞尔曲线
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    // 垂直于径向的微小偏移，让连线略有弧度
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final perpX = len > 0 ? -dy / len * 8 : 0.0;
    final perpY = len > 0 ? dx / len * 8 : 0.0;
    final ctrl = Offset(mid.dx + perpX, mid.dy + perpY);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MindMapPainter oldDelegate) {
    if (oldDelegate.center != center) return true;
    if (oldDelegate.categoryRadius != categoryRadius) return true;
    if (oldDelegate.leafBaseOffset != leafBaseOffset) return true;
    if (oldDelegate.leafSpacing != leafSpacing) return true;
    if (oldDelegate.lineColor != lineColor) return true;
    if (!setEquals(oldDelegate.collapsed, collapsed)) return true;
    if (oldDelegate.categories.length != categories.length) return true;
    for (int i = 0; i < categories.length; i++) {
      if (categories[i].value.length !=
          oldDelegate.categories[i].value.length) {
        return true;
      }
    }
    return false;
  }
}

IconData _profileCategoryIcon(String category) {
  return switch (category) {
    'basic_info' => Icons.badge_outlined,
    'interests' => Icons.interests_outlined,
    'personality' => Icons.psychology_outlined,
    'habits' => Icons.schedule_outlined,
    'work_study' => Icons.school_outlined,
    'preferences' => Icons.favorite_border_rounded,
    'social' => Icons.people_outline_rounded,
    'health' => Icons.health_and_safety_outlined,
    _ => Icons.bookmark_border_rounded,
  };
}

class _CategoryNode extends StatelessWidget {
  final String category;
  final int count;
  final bool isCollapsed;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onSupplement;

  const _CategoryNode({
    required this.category,
    required this.count,
    required this.isCollapsed,
    required this.isLoading,
    required this.onTap,
    required this.onSupplement,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = ProfileEntry.categoryLabels[category] ?? category;
    final icon = _profileCategoryIcon(category);

    return Material(
      color: const Color(0x00000000),
      child: Container(
        width: 152,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space3,
          vertical: AppTheme.space2,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: AppTheme.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$count 条观察',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            // 右上角"补充此项"按钮
            Positioned(
              right: -8,
              top: -8,
              child: SizedBox(
                width: 32,
                height: 32,
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: scheme.primary,
                        ),
                        onPressed: onSupplement,
                        tooltip: '补充此项',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeafNode extends StatelessWidget {
  final ProfileEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LeafNode({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onEdit,
      onLongPress: () => _showMenu(context),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(AppTheme.space3),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTheme.space2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    '${entry.confidence}%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              entry.value,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              '${profileSourceLabel(entry.source)} · '
              '${entry.updatedAt.month}/${entry.updatedAt.day}',
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.get('edit')),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                l10n.get('delete'),
                style: TextStyle(color: scheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类专属问卷对话框（AI 生成的 1-3 个问题）
class _CategoryQuestionDialog extends StatefulWidget {
  final String category;
  final List<ProfileQuestion> questions;
  final Future<void> Function(List<ProfileEntryDraft>) onSave;

  const _CategoryQuestionDialog({
    required this.category,
    required this.questions,
    required this.onSave,
  });

  @override
  State<_CategoryQuestionDialog> createState() =>
      _CategoryQuestionDialogState();
}

class _CategoryQuestionDialogState extends State<_CategoryQuestionDialog> {
  int _current = 0;
  bool _saving = false;
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.questions.length; i++) {
      _controllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final entries = <ProfileEntryDraft>[];
    for (int i = 0; i < widget.questions.length; i++) {
      final answer = _controllers[i].text.trim();
      if (answer.isEmpty) continue;
      entries.add(
        ProfileEntryDraft(
          category: widget.category,
          key: widget.questions[i].suggestedKey,
          value: answer,
          confidence: 90,
          source: 'category_supplement',
        ),
      );
    }
    try {
      await widget.onSave(entries);
    } catch (e) {
      debugPrint('[CategoryQuestionDialog] create profiles failed: $e');
    }
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
    }
  }

  void _next() {
    if (_current < widget.questions.length - 1) {
      setState(() => _current++);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_current > 0) setState(() => _current--);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final q = widget.questions[_current];
    final icon = ProfileEntry.categoryIcons[widget.category] ?? '📌';
    final label =
        ProfileEntry.categoryLabels[widget.category] ?? widget.category;
    final isLast = _current == widget.questions.length - 1;

    return AlertDialog(
      title: Text('$icon $label'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n
                  .get('questionProgress')
                  .replaceAll('{n}', (_current + 1).toString())
                  .replaceAll('{total}', widget.questions.length.toString()),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              q.question,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controllers[_current],
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.get('profileInitHint'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_current > 0)
          TextButton(onPressed: _prev, child: Text(l10n.get('previous'))),
        TextButton(
          onPressed: () {
            _controllers[_current].clear();
            _next();
          },
          child: Text(l10n.get('skip')),
        ),
        FilledButton(
          onPressed: _saving ? null : (isLast ? _finish : _next),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isLast ? l10n.get('finish') : l10n.get('next')),
        ),
      ],
    );
  }
}
