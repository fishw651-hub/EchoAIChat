import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/plan_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/permission_service.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  @override
  void initState() {
    super.initState();
    // 首次打开计划消息面板时申请后台/自启动权限
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    final alreadyDone = await PermissionService.hasRequested();
    if (alreadyDone) return;

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // 先弹说明 dialog，再申请权限
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启后台运行权限'),
        content: Text(
          '为了让计划消息能在应用被关闭后仍然按时触发，需要授予以下权限：\n\n'
          '• 通知权限（必须）\n'
          '• 精确闹钟权限（必须）\n'
          '• 电池优化白名单（推荐）\n'
          '• 自启动权限（国产手机推荐）\n\n'
          '这些权限仅用于本地按时触发计划消息，不会上传任何信息。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.get('later'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去授权')),
        ],
      ),
    );
    if (shouldProceed != true) return;

    await PermissionService.requestPlanPermissions();

    if (!mounted) return;
    // 国产 ROM 引导自启动
    if (PermissionService.needsAutoStartGuide) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('开启自启动'),
          content: Text(
            '检测到您的设备可能限制了应用自启动。\n'
            '建议前往系统设置中找到本应用，开启"自启动"和"后台运行"权限，以确保计划消息能在后台按时触发。',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我知道了')),
          ],
        ),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('权限申请完成'),
        backgroundColor: scheme.primaryContainer,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(planProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('plannedMessagesTitle'))),
      body: state.plannedMessages.isEmpty
          ? Center(child: Text(l10n.get('noPlannedMessages')))
          : ListView.builder(
              itemCount: state.plannedMessages.length,
              itemBuilder: (_, i) {
                final plan = state.plannedMessages[i];
                final isPast = plan.scheduledTime.isBefore(DateTime.now());
                return Card(
                  child: ListTile(
                    leading: Icon(
                      plan.delivered ? Icons.check_circle : Icons.schedule,
                      color: plan.delivered
                          ? scheme.tertiary
                          : isPast
                              ? scheme.error
                              : scheme.primary,
                    ),
                    title: Text(
                      DateFormat('yyyy-MM-dd HH:mm')
                          .format(plan.scheduledTime),
                      style: TextStyle(
                        fontSize: 14,
                        color: isPast ? scheme.onSurfaceVariant : null,
                        decoration: plan.delivered
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text(plan.message,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!plan.delivered)
                          IconButton(
                            icon: Icon(Icons.play_arrow, color: scheme.tertiary),
                            tooltip: l10n.get('triggerNow'),
                            onPressed: () {
                              ref
                                  .read(planProvider.notifier)
                                  .triggerNow(plan.id!);
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.cancel, color: scheme.error),
                          tooltip: l10n.get('cancelPlan'),
                          onPressed: () {
                            ref
                                .read(planProvider.notifier)
                                .cancelPlan(plan.id!);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
