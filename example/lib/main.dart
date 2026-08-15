import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DxtrBox.init();
  runApp(const DxtrBoxExample());
}

class DxtrBoxExample extends StatelessWidget {
  const DxtrBoxExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('dxtr_box 0.1.0')),
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final box = await DxtrBox.open('demo');
              final sw = Stopwatch()..start();
              for (var i = 0; i < 1000; i++) {
                await box.put('key_$i', <String, dynamic>{
                  'index': i,
                  'active': true,
                });
              }
              sw.stop();
              debugPrint('dxtr_box: 1000 puts in ${sw.elapsedMilliseconds} ms');
            },
            child: const Text('Run dxtr_box smoke benchmark'),
          ),
        ),
      ),
    );
  }
}
