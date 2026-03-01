import 'installer_models.dart';

const List<SoftwareDefinition> kMainSoftwareCatalog = <SoftwareDefinition>[
  SoftwareDefinition(
    id: 'main_hub',
    name: 'InstallHub Core',
    versions: <SoftwareVersionDefinition>[
      SoftwareVersionDefinition(
        version: '2.4.0',
        dependencies: <DependencyOption>[
          DependencyOption(
            id: 'dep_runtime',
            name: 'Runtime Core',
            supportedVersions: <String>['2.1.0', '2.0.4'],
            defaultVersion: '2.1.0',
          ),
          DependencyOption(
            id: 'dep_sync',
            name: 'Sync Agent',
            supportedVersions: <String>['1.8.2', '1.8.0'],
            defaultVersion: '1.8.2',
          ),
        ],
      ),
      SoftwareVersionDefinition(
        version: '2.3.2',
        dependencies: <DependencyOption>[
          DependencyOption(
            id: 'dep_runtime',
            name: 'Runtime Core',
            supportedVersions: <String>['2.0.4'],
            defaultVersion: '2.0.4',
          ),
          DependencyOption(
            id: 'dep_sync',
            name: 'Sync Agent',
            supportedVersions: <String>['1.8.0'],
            defaultVersion: '1.8.0',
          ),
        ],
      ),
    ],
  ),
  SoftwareDefinition(
    id: 'main_media',
    name: 'Media Studio',
    versions: <SoftwareVersionDefinition>[
      SoftwareVersionDefinition(
        version: '5.1.0',
        dependencies: <DependencyOption>[
          DependencyOption(
            id: 'dep_codec',
            name: 'Codec Pack',
            supportedVersions: <String>['3.4.1', '3.2.0'],
            defaultVersion: '3.4.1',
          ),
          DependencyOption(
            id: 'dep_bridge',
            name: 'Device Bridge',
            supportedVersions: <String>['1.2.0'],
            defaultVersion: '1.2.0',
          ),
        ],
      ),
      SoftwareVersionDefinition(
        version: '5.0.3',
        dependencies: <DependencyOption>[
          DependencyOption(
            id: 'dep_codec',
            name: 'Codec Pack',
            supportedVersions: <String>['3.2.0'],
            defaultVersion: '3.2.0',
          ),
          DependencyOption(
            id: 'dep_bridge',
            name: 'Device Bridge',
            supportedVersions: <String>['1.2.0'],
            defaultVersion: '1.2.0',
          ),
        ],
      ),
    ],
  ),
  SoftwareDefinition(
    id: 'main_secure',
    name: 'Secure Vault',
    versions: <SoftwareVersionDefinition>[
      SoftwareVersionDefinition(
        version: '1.9.5',
        dependencies: <DependencyOption>[
          DependencyOption(
            id: 'dep_crypto',
            name: 'Crypto Module',
            supportedVersions: <String>['4.0.0', '3.9.1'],
            defaultVersion: '4.0.0',
          ),
        ],
      ),
      SoftwareVersionDefinition(
        version: '1.8.9',
        dependencies: <DependencyOption>[
          DependencyOption(
            id: 'dep_crypto',
            name: 'Crypto Module',
            supportedVersions: <String>['3.9.1'],
            defaultVersion: '3.9.1',
          ),
        ],
      ),
    ],
  ),
];

const Map<String, List<String>> kPartnerSoftwareAccess = <String, List<String>>{
  'PA01': <String>['main_hub', 'main_media'],
  'QA77': <String>['main_hub', 'main_secure'],
  'ZH12': <String>['main_secure'],
  'MX88': <String>['main_media', 'main_secure'],
};
