import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'activation_service.dart';

class ActivationScreen extends StatefulWidget {
  final ActivationService activation;
  const ActivationScreen({super.key, required this.activation});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _code = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_submitting) return;
    setState(() { _submitting = true; _error = null; });
    final error = await widget.activation.activate(_code.text);
    if (!mounted) return;
    setState(() { _submitting = false; _error = error; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_person_rounded, size: 64,
            color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          const Text('心屿 OS · 邀请制内测', style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('一个激活码仅对应一台设备。新版短码和旧版激活码都可以使用。',
            textAlign: TextAlign.center),
          const SizedBox(height: 26),
          Align(alignment: Alignment.centerLeft,
            child: Text('本机设备编号', style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: SelectableText(widget.activation.deviceCode,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              IconButton(tooltip: '复制设备编号', icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.activation.deviceCode));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('设备编号已复制，请发给邀请人领取激活码')));
                }),
            ]))),
          const SizedBox(height: 22),
          Align(alignment: Alignment.centerLeft,
            child: Text('激活码', style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(height: 8),
          TextField(controller: _code, maxLines: 3, minLines: 2,
            autocorrect: false, enableSuggestions: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: '粘贴你收到的激活码（支持新版短码）')),
          Align(alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.content_paste_outlined),
              label: const Text('一键从剪贴板粘贴'),
              onPressed: () async {
                final clipboard = await Clipboard.getData('text/plain');
                if (!mounted) return;
                setState(() => _code.text = clipboard?.text?.trim() ?? '');
              },
            )),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _submitting ? null : _activate,
            icon: _submitting ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)) :
              const Icon(Icons.verified_user_outlined),
            label: const Text('验证并激活'),
          )),
          const SizedBox(height: 16),
          const Text('无需注册账户，也不需要应用自建服务器。激活后再填写你自己的模型 API Key。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
    ))),
  );
}
