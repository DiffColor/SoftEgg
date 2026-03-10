import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_egg_packager/src/services/local_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('마지막 export root를 저장하고 다시 불러온다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const service = LocalSettingsService();
    final updated = await service.updateExportRoot('/tmp/soft-egg-output');
    final reloaded = await service.load();

    expect(updated.exportRootPath, '/tmp/soft-egg-output');
    expect(reloaded.exportRootPath, '/tmp/soft-egg-output');
  });

  test('기본 export root는 Documents/SoftEgg를 사용한다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const service = LocalSettingsService();
    final settings = await service.load();

    expect(
      settings.exportRootPath.replaceAll('\\', '/'),
      endsWith('/Documents/SoftEgg'),
    );
  });

  test('macOS 샌드박스 Documents 경로는 실제 사용자 Documents로 교정한다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'softegg.last_export_root':
          '/Users/jazzlife/Library/Containers/com.example.softEggPackager/Data/Documents/SoftEgg',
    });

    const service = LocalSettingsService();
    final settings = await service.load();

    expect(
      settings.exportRootPath.replaceAll('\\', '/'),
      '/Users/jazzlife/Documents/SoftEgg',
    );
  });
}
