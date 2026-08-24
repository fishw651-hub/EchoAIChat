import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/novel_service.dart';

class NovelHistoryScreen extends StatefulWidget {
  const NovelHistoryScreen({super.key});

  @override
  State<NovelHistoryScreen> createState() => _NovelHistoryScreenState();
}

class _NovelHistoryScreenState extends State<NovelHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await NovelService.getAll();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小说生成')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('暂无生成记录'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final ts = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int);
                    final preview = (item['result'] as String).length > 80
                        ? '${(item['result'] as String).substring(0, 80)}...'
                        : item['result'] as String;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text('${item['style']} · ${item['word_count']}字',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                          Text('${ts.month}/${ts.day} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ]),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error),
                          onPressed: () async {
                            await NovelService.delete(item['id'] as int);
                            _load();
                          },
                        ),
                        onTap: () => _showDetail(context, item),
                      ),
                    );
                  },
                ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item['style']} · ${item['word_count']}字'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(item['result'] as String, style: const TextStyle(fontSize: 14, height: 1.6))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          TextButton(onPressed: () {
            Clipboard.setData(ClipboardData(text: item['result'] as String));
            Navigator.pop(ctx);
          }, child: const Text('复制')),
        ],
      ),
    );
  }
}
