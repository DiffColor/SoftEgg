import 'package:flutter_test/flutter_test.dart';
import 'package:soft_egg_packager/src/data/catalog_api_client.dart';
import 'package:soft_egg_packager/src/data/catalog_repository.dart';
import 'package:soft_egg_packager/src/models/packaging_models.dart';

void main() {
  test('데스크톱 패키지가 없으면 진단 정보가 포함된 예외를 던진다', () async {
    final repository = CatalogRepository(
      apiClient: _FakeCatalogApiClient(
        CompanyCatalog(
          company: CompanyInfo(
            companyNodeId: 'org-root',
            companyName: 'Turtle Lab',
            companyCode: 'ABCDE',
            issuedAt: DateTime.parse('2026-03-10T00:00:00+09:00'),
            expiresAt: DateTime.parse('2026-03-11T00:00:00+09:00'),
          ),
          softwarePackages: <RemoteSoftwarePackage>[
            RemoteSoftwarePackage(
              id: 'pkg-android',
              name: 'EzDID',
              codeName: 'ezdid',
              productId: 1,
              version: '1.0.0',
              os: 'android',
              releaseChannel: 'stable',
              price: 0,
              mainBinary: const RemoteSoftwareBinary(
                name: 'main.apk',
                version: '1.0.0',
                uri: 'ftp://example.test/main.apk',
                checksum: 'abc123',
              ),
              dependencies: const <RemoteSoftwareBinary>[],
              installOptions: const RemoteInstallOptions(
                desktopShortcuts: <RemoteInstallEntry>[],
                startupPrograms: <RemoteInstallEntry>[],
                shortcutName: '',
                desktopShortcutTargets: <String>[],
                startupTargets: <String>[],
              ),
            ),
          ],
        ),
      ),
    );

    await expectLater(
      repository.fetchCatalog('ABCDE'),
      throwsA(
        isA<CatalogException>()
            .having((error) => error.error, 'error', 'no_desktop_software')
            .having(
              (error) => error.message,
              'message',
              contains('companyCode=ABCDE'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('total=1, desktop=0, os=[android:1]'),
            ),
      ),
    );
  });
}

class _FakeCatalogApiClient extends CatalogApiClient {
  _FakeCatalogApiClient(this.catalog) : super(baseUrl: 'https://example.test');

  final CompanyCatalog catalog;

  @override
  Future<CompanyCatalog> fetchCatalog(String companyCode) async => catalog;
}
