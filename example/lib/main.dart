import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BoxStore.init();
  runApp(const DxtrBoxExample());
}

class DxtrBoxExample extends StatelessWidget {
  const DxtrBoxExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('dxtr_box 0.7')),
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final box = await BoxStore.open('demo');
              try {
                await box.put('settings', <String, dynamic>{
                  'theme': 'dark',
                  'launchCount': 1,
                });
                final value = await box.get('settings');
                debugPrint('dxtr_box settings: $value');
              } finally {
                await box.close();
              }
            },
            child: const Text('Write and read dxtr_box'),
          ),
        ),
      ),
    );
  }
}
