import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/import/import_controller.dart';

import '../support/fakes.dart';

void main() {
  late FakeImporter importer;
  late FakePicker picker;
  late ProviderContainer container;

  setUp(() {
    importer = FakeImporter();
    picker = FakePicker();
    container = ProviderContainer(
      overrides: [
        importerProvider.overrideWithValue(importer),
        filePickerProvider.overrideWithValue(picker),
      ],
    );
    addTearDown(() => container.dispose());
  });

  ImportState state() => container.read(importControllerProvider);
  ImportController controller() =>
      container.read(importControllerProvider.notifier);

  test('starts idle', () {
    expect(state(), isA<ImportIdle>());
  });

  test('start runs with progress and ends with the summary', () async {
    final run = controller().start(['/a/1.mp3', '/a/2.mp3']);

    final running = state() as ImportRunning;
    expect(running.hidden, isFalse);
    expect(running.progress.done, 0);
    expect(running.progress.total, 2);

    importer.progress(1, 2, '2.mp3');
    final next = state() as ImportRunning;
    expect(next.progress.done, 1);
    expect(next.progress.currentName, '2.mp3');

    importer.finish(summary47);
    await run;
    expect((state() as ImportDone).summary, same(summary47));
  });

  test('hide sets hidden and keeps it on progress', () async {
    final run = controller().start(['/a/1.mp3', '/a/2.mp3']);
    controller().hide();
    expect((state() as ImportRunning).hidden, isTrue);

    importer.progress(1, 2, '2.mp3');
    expect((state() as ImportRunning).hidden, isTrue);

    importer.finish(summary47);
    await run;
    expect(state(), isA<ImportDone>());
  });

  test('dismiss returns to idle', () async {
    final run = controller().start(['/a/1.mp3']);
    importer.finish(summary47);
    await run;
    controller().dismiss();
    expect(state(), isA<ImportIdle>());
  });

  test('dismiss is ignored while running', () {
    controller().start(['/a/1.mp3']);
    controller().dismiss();
    expect(state(), isA<ImportRunning>());
  });

  test('a second start while running is ignored', () async {
    final run = controller().start(['/a/1.mp3']);
    await controller().start(['/b/2.mp3']);
    expect(importer.calls, [
      ['/a/1.mp3'],
    ]);
    importer.finish(summary47);
    await run;
    expect(state(), isA<ImportDone>());
  });

  test('start with no paths stays idle', () async {
    await controller().start([]);
    expect(state(), isA<ImportIdle>());
    expect(importer.calls, isEmpty);
  });

  test('a failing import ends in ImportFailed with the message', () async {
    final run = controller().start(['/a/1.mp3']);
    importer.fail(const FileSystemExceptionLike('disk full'));
    await run;
    expect((state() as ImportFailed).message, contains('disk full'));
    controller().dismiss();
    expect(state(), isA<ImportIdle>());
  });

  test('pickAndImport imports the picked paths', () async {
    picker.result = ['/a/1.mp3', '/a/2.mp3'];
    final run = controller().pickAndImport();
    await pumpEventQueue();
    expect(importer.calls, [
      ['/a/1.mp3', '/a/2.mp3'],
    ]);
    expect(picker.cleanups, 0);
    importer.finish(summary47);
    await run;
    expect(state(), isA<ImportDone>());
    expect(picker.cleanups, 1);
  });

  test('pickAndImport does nothing when the picker returns nothing', () async {
    await controller().pickAndImport();
    expect(picker.picks, 1);
    expect(importer.calls, isEmpty);
    expect(state(), isA<ImportIdle>());
  });

  test('a failing picker ends in ImportFailed', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        importerProvider.overrideWithValue(importer),
        filePickerProvider.overrideWithValue(_ThrowingPicker()),
      ],
    );
    await controller().pickAndImport();
    expect(
      (state() as ImportFailed).message,
      contains('Could not open the file picker'),
    );
    expect(importer.calls, isEmpty);
  });

  test('pickAndImport is ignored while an import runs', () async {
    final run = controller().start(['/a/1.mp3']);
    await controller().pickAndImport();
    expect(picker.picks, 0);
    importer.finish(summary47);
    await run;
  });
}

class _ThrowingPicker extends FakePicker {
  @override
  Future<List<String>> pick() async => throw StateError('no portal');
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike(this.message);

  final String message;

  @override
  String toString() => 'FileSystemException: $message';
}
