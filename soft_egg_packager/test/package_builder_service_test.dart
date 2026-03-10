import 'package:flutter_test/flutter_test.dart';
import 'package:soft_egg_packager/src/models/packaging_models.dart';
import 'package:soft_egg_packager/src/services/checksum_service.dart';
import 'package:soft_egg_packager/src/services/ftp_download_service.dart';
import 'package:soft_egg_packager/src/services/local_settings_service.dart';
import 'package:soft_egg_packager/src/services/package_builder_service.dart';

void main() {
  test('메인 바이너리 경로가 없으면 패키징을 차단한다', () async {
    final service = PackageBuilderService(
      ftpDownloadService: const FtpDownloadService(),
      checksumService: const ChecksumService(),
    );

    final settings = const SoftEggSettings(
      apiBaseUrl: 'https://licensehub.ilycode.app',
      ftpHost: 'example.test',
      ftpUser: 'user',
      ftpPassword: 'pass',
      exportRootPath: '/tmp',
    );

    final company = CompanyInfo(
      companyNodeId: 'org-root',
      companyName: 'Turtle Lab',
      companyCode: 'U4HHP',
      issuedAt: DateTime.parse('2026-03-10T00:00:00+09:00'),
      expiresAt: DateTime.parse('2026-03-11T00:00:00+09:00'),
    );

    final softwarePackage = RemoteSoftwarePackage(
      id: 'pkg-1',
      name: 'EzDID',
      codeName: 'ezdid',
      productId: 1,
      version: '1.0.0',
      os: 'windows',
      releaseChannel: 'stable',
      price: 0,
      mainBinary: const RemoteSoftwareBinary(
        name: 'missing.exe',
        version: '1.0.0',
        uri: '',
        checksum: '',
      ),
      dependencies: const <RemoteSoftwareBinary>[],
      installOptions: const RemoteInstallOptions(
        desktopShortcuts: <RemoteInstallEntry>[],
        startupPrograms: <RemoteInstallEntry>[],
        shortcutName: '',
        desktopShortcutTargets: <String>[],
        startupTargets: <String>[],
      ),
    );

    expect(
      () => service.build(
        settings: settings,
        company: company,
        softwarePackage: softwarePackage,
        selectedDependencies: const <RemoteSoftwareBinary>[],
        onProgress: (_) {},
      ),
      throwsA(isA<PackageBuildException>()),
    );
  });
}
