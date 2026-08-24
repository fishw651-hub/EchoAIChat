import 'package:flutter/material.dart';

/// 邮箱输入组件：前缀输入框 + 后缀下拉框（含自定义）
///
/// 常见邮箱后缀预设 + "自定义"选项（用户可输入任意后缀）
/// 完整邮箱通过 [controller] 暴露给外部（已自动拼接 prefix@suffix）
class EmailInputField extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? helperText;
  final Widget? prefixIcon;
  final InputDecoration? decoration;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;

  const EmailInputField({
    super.key,
    required this.controller,
    this.labelText,
    this.helperText,
    this.prefixIcon,
    this.decoration,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  /// 常见邮箱后缀
  static const List<String> presetDomains = [
    '@qq.com',
    '@163.com',
    '@126.com',
    '@sina.com',
    '@sohu.com',
    '@139.com',
    '@189.cn',
    '@aliyun.com',
    '@foxmail.com',
    '@outlook.com',
    '@hotmail.com',
    '@live.com',
    '@gmail.com',
    '@yahoo.com',
    '@icloud.com',
    '@263.net',
    '@vip.qq.com',
  ];

  @override
  State<EmailInputField> createState() => _EmailInputFieldState();
}

class _EmailInputFieldState extends State<EmailInputField> {
  final _prefixCtrl = TextEditingController();
  String _selectedSuffix = EmailInputField.presetDomains.first;
  bool _customMode = false;
  final _customSuffixCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 初始化：如果 controller 已有值，尝试解析
    _parseFromController();
    _prefixCtrl.addListener(_syncToController);
    _customSuffixCtrl.addListener(_syncToController);
    widget.controller.addListener(_parseFromControllerExternal);
  }

  void _parseFromController() {
    final v = widget.controller.text;
    if (v.isEmpty || !v.contains('@')) return;
    final at = v.indexOf('@');
    final prefix = v.substring(0, at);
    final suffix = v.substring(at);
    _prefixCtrl.text = prefix;
    if (EmailInputField.presetDomains.contains(suffix)) {
      _selectedSuffix = suffix;
      _customMode = false;
    } else {
      _customMode = true;
      _customSuffixCtrl.text = suffix;
    }
  }

  void _parseFromControllerExternal() {
    final v = widget.controller.text;
    final expected = _buildEmail();
    if (v != expected && v.isNotEmpty) {
      _parseFromController();
    }
  }

  String _buildEmail() {
    final prefix = _prefixCtrl.text.trim();
    if (prefix.isEmpty) return '';
    final suffix = _customMode
        ? _customSuffixCtrl.text.trim()
        : _selectedSuffix;
    if (suffix.isEmpty || !suffix.startsWith('@')) return '';
    return '$prefix$suffix';
  }

  void _syncToController() {
    final email = _buildEmail();
    if (widget.controller.text != email) {
      widget.controller.text = email;
    }
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _customSuffixCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveDecoration = widget.decoration ??
        InputDecoration(
          labelText: widget.labelText ?? '邮箱',
          helperText: widget.helperText,
          prefixIcon: widget.prefixIcon ?? const Icon(Icons.email_outlined),
          border: const OutlineInputBorder(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 前缀输入框
        TextField(
          controller: _prefixCtrl,
          decoration: effectiveDecoration.copyWith(
            labelText: widget.labelText ?? '邮箱前缀',
            helperText: null,
          ),
          keyboardType: TextInputType.text,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onFieldSubmitted != null
              ? (_) => widget.onFieldSubmitted!(_buildEmail())
              : null,
        ),
        const SizedBox(height: 8),
        // 后缀选择/自定义输入
        Row(
          children: [
            Expanded(
              child: _customMode
                  ? TextField(
                      controller: _customSuffixCtrl,
                      decoration: InputDecoration(
                        labelText: '自定义后缀',
                        hintText: '@example.com',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          tooltip: '切换为预设',
                          onPressed: () {
                            setState(() {
                              _customMode = false;
                              _customSuffixCtrl.clear();
                              _syncToController();
                            });
                          },
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => _syncToController(),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _selectedSuffix,
                      decoration: const InputDecoration(
                        labelText: '邮箱后缀',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ...EmailInputField.presetDomains.map((d) =>
                            DropdownMenuItem(value: d, child: Text(d))),
                        const DropdownMenuItem(
                          value: '__custom__',
                          child: Row(children: [
                            Icon(Icons.edit, size: 14),
                            SizedBox(width: 4),
                            Text('自定义'),
                          ]),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == '__custom__') {
                          setState(() {
                            _customMode = true;
                            _customSuffixCtrl.text = '@';
                          });
                        } else if (v != null) {
                          setState(() {
                            _selectedSuffix = v;
                          });
                          _syncToController();
                        }
                      },
                    ),
            ),
          ],
        ),
        if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              widget.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
