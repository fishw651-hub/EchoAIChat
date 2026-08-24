import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/sticker.dart';
import '../services/sticker_service.dart';

class StickerPanel extends StatefulWidget {
  final List<Sticker> stickers;
  final ValueChanged<Sticker> onSelected;
  final Future<void> Function() onChanged;

  const StickerPanel({
    super.key,
    required this.stickers,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  bool _manage = false;
  bool _adding = false;
  final _descriptionController = TextEditingController();
  String? _sourcePath;
  late List<Sticker> _stickers;

  @override
  void initState() {
    super.initState();
    _stickers = List.of(widget.stickers);
  }

  Future<void> _reload() async {
    final stickers = await StickerService.listActive();
    if (mounted) setState(() => _stickers = stickers);
    await widget.onChanged();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _sourcePath = picked.path);
  }

  Future<void> _save() async {
    final path = _sourcePath;
    if (path == null) return;
    try {
      await StickerService.add(
        sourcePath: path,
        description: _descriptionController.text,
      );
      if (!mounted) return;
      setState(() {
        _adding = false;
        _sourcePath = null;
        _descriptionController.clear();
      });
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _edit(Sticker sticker) async {
    final controller = TextEditingController(text: sticker.description);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改表情描述'),
        content: TextField(
          controller: controller,
          maxLength: 30,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await StickerService.updateDescription(sticker.id, value);
    await _reload();
  }

  Future<void> _delete(Sticker sticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除表情？'),
        content: Text('将删除“${sticker.description}”的快捷入口。历史消息仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StickerService.delete(sticker.id);
      await _reload();
    }
  }

  Future<void> _manageSticker(Sticker sticker) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改描述'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') await _edit(sticker);
    if (action == 'delete') await _delete(sticker);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_adding) {
      return _buildAdd(context, scheme);
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _manage ? '管理表情' : '我的表情',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _manage = !_manage),
                  child: Text(_manage ? '完成' : '管理'),
                ),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: .9,
              ),
              itemCount: _stickers.length + (_manage ? 0 : 1),
              itemBuilder: (context, index) {
                if (!_manage && index == _stickers.length) {
                  return InkWell(
                    onTap: () => setState(() => _adding = true),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '添加',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                }
                final sticker = _stickers[index];
                return InkWell(
                  onTap: _manage
                      ? () => _manageSticker(sticker)
                      : () => widget.onSelected(sticker),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _image(sticker),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sticker.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdd(BuildContext context, ColorScheme scheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('添加表情', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _adding = false),
                  child: const Text('取消'),
                ),
              ],
            ),
            Semantics(
              button: true,
              label: _sourcePath == null ? '添加本地图片' : '重新选择本地图片',
              child: Material(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.72),
                  ),
                ),
                child: InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox.square(
                    key: const ValueKey('stickerImagePicker'),
                    dimension: 128,
                    child: _sourcePath == null
                        ? Icon(
                            Icons.add_rounded,
                            size: 48,
                            color: scheme.primary,
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (!kIsWeb)
                                  Image.file(
                                    File(_sourcePath!),
                                    fit: BoxFit.cover,
                                  )
                                else
                                  Icon(
                                    Icons.check_rounded,
                                    size: 42,
                                    color: scheme.primary,
                                  ),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: scheme.surface.withValues(
                                        alpha: 0.88,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 17,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLength: 30,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            FilledButton(
              onPressed: _sourcePath == null ? null : _save,
              child: const Text('保存到全局表情库'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(Sticker sticker) {
    if (File(sticker.imagePath).existsSync()) {
      return Image.file(File(sticker.imagePath), fit: BoxFit.cover);
    }
    return const Center(child: Icon(Icons.broken_image_outlined));
  }
}
