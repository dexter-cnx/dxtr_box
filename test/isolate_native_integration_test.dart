import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _isolateWorker(Map<String, Object?> message) async {
  final rootPath = message['rootPath']! as String;
  final worker = message['worker']! as int;
  final parent = message['parent']! as SendPort;
  final control = ReceivePort();
  Box? box;

  try {
    await DxtrBox.init(path: rootPath);
    box = await DxtrBox.open('isolate-shared');
    await box.put('worker-$worker-0', worker);

    parent.send(<String, Object?>{
      'type': 'ready',
      'worker': worker,
      'control': control.sendPort,
    });

    final peerKey = await control.first as String;
    final peerValue = await box.get(peerKey);
    if (peerValue == null) {
      throw StateError('worker $worker could not observe $peerKey');
    }

    for (var offset = 1; offset < 32; offset++) {
      await box.put('worker-$worker-$offset', <String, int>{
        'worker': worker,
        'offset': offset,
      });
    }

    await box.close();
    box = null;
    control.close();

    parent.send(<String, Object?>{
      'type': 'done',
      'worker': worker,
      'peerValue': peerValue,
    });
  } catch (error, stackTrace) {
    control.close();
    if (box != null) {
      try {
        await box.close();
      } catch (closeError, closeStackTrace) {
        parent.send(<String, Object?>{
          'type': 'error',
          'worker': worker,
          'error': '$error; close failed: $closeError',
          'stackTrace': '$stackTrace\n$closeStackTrace',
        });
        return;
      }
    }
    parent.send(<String, Object?>{
      'type': 'error',
      'worker': worker,
      'error': '$error',
      'stackTrace': '$stackTrace',
    });
  }
}

void main() {
  final nativeEnabled = Platform.environment['DXTR_BOX_NATIVE_TEST'] == '1';

  test(
    'independent Dart isolates share committed FRB storage safely',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_isolate_native_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      final events = ReceivePort();
      addTearDown(events.close);

      await Future.wait(<Future<Isolate>>[
        Isolate.spawn<Map<String, Object?>>(
          _isolateWorker,
          <String, Object?>{
            'rootPath': root.path,
            'worker': 0,
            'parent': events.sendPort,
          },
        ),
        Isolate.spawn<Map<String, Object?>>(
          _isolateWorker,
          <String, Object?>{
            'rootPath': root.path,
            'worker': 1,
            'parent': events.sendPort,
          },
        ),
      ]);

      final controls = <int, SendPort>{};
      final done = <int, Object?>{};
      final completer = Completer<void>();
      late final StreamSubscription<Object?> subscription;
      subscription = events.listen((Object? raw) {
        final event = raw! as Map<Object?, Object?>;
        final type = event['type'];
        final worker = event['worker']! as int;
        if (type == 'ready') {
          controls[worker] = event['control']! as SendPort;
          if (controls.length == 2) {
            controls[0]!.send('worker-1-0');
            controls[1]!.send('worker-0-0');
          }
          return;
        }
        if (type == 'done') {
          done[worker] = event['peerValue'];
          if (done.length == 2 && !completer.isCompleted) {
            completer.complete();
          }
          return;
        }
        if (type == 'error' && !completer.isCompleted) {
          completer.completeError(
            StateError(
              'isolate $worker failed: ${event['error']}\n${event['stackTrace']}',
            ),
          );
        }
      });

      await completer.future.timeout(const Duration(seconds: 20));
      await subscription.cancel();

      expect(done[0], 1);
      expect(done[1], 0);

      await DxtrBox.init(path: root.path);
      final reopened = await DxtrBox.open('isolate-shared');
      expect(reopened.length, 64);
      expect(await reopened.get('worker-0-0'), 0);
      expect(await reopened.get('worker-1-0'), 1);
      expect(await reopened.get('worker-0-31'), <String, int>{
        'worker': 0,
        'offset': 31,
      });
      expect(await reopened.get('worker-1-31'), <String, int>{
        'worker': 1,
        'offset': 31,
      });
      await reopened.close();
    },
    skip:
        nativeEnabled ? false : 'Set DXTR_BOX_NATIVE_TEST=1 to run native IO.',
  );
}
