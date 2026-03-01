import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softegg_app/src/domain/installer_models.dart';
import 'package:softegg_app/src/services/install_runtime_service.dart';
import 'package:softegg_app/src/services/softegg_snapshot_service.dart';
import 'package:softegg_app/src/state/softegg_controller.dart';
import 'package:softegg_app/src/ui/softegg_page.dart';

class _FakeSnapshotService extends SoftEggSnapshotService {
  @override
  Future<List<SoftEggSnapshotRef>> listSnapshots() async =>
      <SoftEggSnapshotRef>[];
}

void main() {
  testWidgets('softegg step1 화면 렌더링', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = SoftEggController(
      snapshotService: _FakeSnapshotService(),
      runtime: InstallRuntimeService(),
    );
    await controller.initialize();

    await tester.pumpWidget(MaterialApp(home: SoftEggPage(controller: controller)));

    expect(find.textContaining('Step 1/4'), findsOneWidget);
    expect(find.textContaining('파트너 필터 입력'), findsOneWidget);
  });
}
