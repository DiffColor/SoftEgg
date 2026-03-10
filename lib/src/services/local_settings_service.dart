import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class SoftEggSettings {
  const SoftEggSettings({
    required this.apiBaseUrl,
    required this.ftpHost,
    required this.ftpUser,
    required this.ftpPassword,
    required this.exportRootPath,
  });

  final String apiBaseUrl;
  final String ftpHost;
  final String ftpUser;
  final String ftpPassword;
  final String exportRootPath;

  SoftEggSettings copyWith({
    String? apiBaseUrl,
    String? ftpHost,
    String? ftpUser,
    String? ftpPassword,
    String? exportRootPath,
  }) {
    return SoftEggSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      ftpHost: ftpHost ?? this.ftpHost,
      ftpUser: ftpUser ?? this.ftpUser,
      ftpPassword: ftpPassword ?? this.ftpPassword,
      exportRootPath: exportRootPath ?? this.exportRootPath,
    );
  }

  bool get hasFtpCredentials {
    return ftpHost.trim().isNotEmpty &&
        ftpUser.trim().isNotEmpty &&
        ftpPassword.trim().isNotEmpty;
  }

  String? get packagingBlocker {
    if (!hasFtpCredentials) {
      return 'FTP 설정이 없어 실제 패키징을 시작할 수 없습니다.';
    }
    return null;
  }
}

class LocalSettingsService {
  const LocalSettingsService();

  static const String _lastExportRootKey = 'softegg.last_export_root';
  static const MethodChannel _securityScopedChannel = MethodChannel(
    'softegg/security_scoped',
  );

  String resolveHomeDirectory() => _resolveHomeDirectory();
  String resolveDefaultExportRoot() =>
      _resolveDefaultExportRootPath(_resolveHomeDirectory());

  Future<SoftEggSettings> load() async {
    final homeDirectory = _resolveHomeDirectory();
    final baseSettings = SoftEggSettings(
      apiBaseUrl: _AppEmbeddedConfig.apiBaseUrl.trim(),
      ftpHost: _AppEmbeddedConfig.ftpHost.trim(),
      ftpUser: _AppEmbeddedConfig.ftpUser.trim(),
      ftpPassword: _AppEmbeddedConfig.ftpPassword.trim(),
      exportRootPath: _resolveDefaultExportRootPath(homeDirectory),
    );

    final preferences = await SharedPreferences.getInstance();
    final persistedExportRoot =
        preferences.getString(_lastExportRootKey)?.trim() ?? '';
    if (persistedExportRoot.isEmpty) {
      await _ensureExportDirectory(baseSettings.exportRootPath);
      return baseSettings;
    }

    final normalizedExportRoot = _normalizeExportRoot(
      persistedExportRoot,
      homeDirectory: homeDirectory,
    );
    final accessibleExportRoot = await _restorePersistedDirectoryAccess(
      normalizedExportRoot,
      defaultExportRoot: baseSettings.exportRootPath,
    );
    if (accessibleExportRoot != persistedExportRoot) {
      await preferences.setString(_lastExportRootKey, accessibleExportRoot);
    }

    final resolvedSettings = baseSettings.copyWith(
      exportRootPath: accessibleExportRoot,
    );
    await _ensureExportDirectory(resolvedSettings.exportRootPath);
    return resolvedSettings;
  }

  Future<SoftEggSettings> updateExportRoot(String rawPath) async {
    final settings = await load();
    final defaultExportRoot = resolveDefaultExportRoot();
    final normalizedPath = _normalizeExportRoot(
      rawPath,
      homeDirectory: _resolveHomeDirectory(),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastExportRootKey, normalizedPath);
    if (!p.equals(settings.exportRootPath, normalizedPath)) {
      await _clearDirectoryAccessIfNeeded(
        settings.exportRootPath,
        defaultExportRoot: defaultExportRoot,
      );
    }
    await _rememberDirectoryAccessIfNeeded(
      normalizedPath,
      defaultExportRoot: defaultExportRoot,
    );
    final resolvedSettings = settings.copyWith(exportRootPath: normalizedPath);
    await _ensureExportDirectory(resolvedSettings.exportRootPath);
    return resolvedSettings;
  }

  Future<SoftEggSettings> resetExportRoot() async {
    final settings = await load();
    final homeDirectory = _resolveHomeDirectory();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastExportRootKey);
    await _clearDirectoryAccessIfNeeded(
      settings.exportRootPath,
      defaultExportRoot: _resolveDefaultExportRootPath(homeDirectory),
    );
    final resolvedSettings = settings.copyWith(
      exportRootPath: _resolveDefaultExportRootPath(homeDirectory),
    );
    await _ensureExportDirectory(resolvedSettings.exportRootPath);
    return resolvedSettings;
  }

  Future<String> _restorePersistedDirectoryAccess(
    String path, {
    required String defaultExportRoot,
  }) async {
    if (!Platform.isMacOS) {
      return path;
    }
    if (p.equals(path, defaultExportRoot)) {
      return path;
    }
    try {
      final restored = await _securityScopedChannel.invokeMethod<String>(
        'restoreDirectory',
        path,
      );
      return restored == null || restored.trim().isEmpty
          ? path
          : p.normalize(restored);
    } on MissingPluginException {
      return path;
    } on PlatformException {
      return path;
    }
  }

  Future<void> _rememberDirectoryAccessIfNeeded(
    String path, {
    required String defaultExportRoot,
  }) async {
    if (!Platform.isMacOS || p.equals(path, defaultExportRoot)) {
      return;
    }
    try {
      await _securityScopedChannel.invokeMethod<void>('rememberDirectory', path);
    } on MissingPluginException {
      // noop on unsupported platforms/tests
    }
  }

  Future<void> _clearDirectoryAccessIfNeeded(
    String path, {
    required String defaultExportRoot,
  }) async {
    if (!Platform.isMacOS || p.equals(path, defaultExportRoot)) {
      return;
    }
    try {
      await _securityScopedChannel.invokeMethod<void>('clearDirectory', path);
    } on MissingPluginException {
      // noop on unsupported platforms/tests
    }
  }

  Future<void> _ensureExportDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  String _resolveHomeDirectory() {
    final home = _readEnv('HOME');
    if (Platform.isMacOS) {
      final sandboxHome = _extractMacOsUserHome(home);
      if (sandboxHome != null) {
        return sandboxHome;
      }
      final fixedHome = _readEnv('CFFIXED_USER_HOME');
      if (fixedHome != null && fixedHome.isNotEmpty) {
        return p.normalize(fixedHome);
      }
      final logName = _readEnv('LOGNAME') ?? _readEnv('USER');
      if (logName != null && logName.isNotEmpty) {
        final candidate = p.join('/Users', logName);
        if (Directory(candidate).existsSync()) {
          return candidate;
        }
      }
    }
    if (home != null && home.isNotEmpty) {
      return p.normalize(home);
    }
    final userProfile = _readEnv('USERPROFILE');
    if (userProfile != null && userProfile.isNotEmpty) {
      return p.normalize(userProfile);
    }
    return p.normalize(Directory.current.path);
  }

  String _resolveDefaultExportRootPath(String homeDirectory) {
    return p.join(homeDirectory, 'Documents', 'SoftEgg');
  }

  String _normalizeExportRoot(String rawPath, {required String homeDirectory}) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Export root 경로가 비어 있습니다.');
    }

    String resolvedPath;
    if (trimmed == '~') {
      resolvedPath = homeDirectory;
    } else if (trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
      resolvedPath = p.join(homeDirectory, trimmed.substring(2));
    } else {
      resolvedPath = trimmed;
    }

    if (!p.isAbsolute(resolvedPath)) {
      throw const FormatException('Export root는 절대 경로로 입력해야 합니다.');
    }

    return _migrateSandboxedDocumentsPath(
      p.normalize(resolvedPath),
      homeDirectory: homeDirectory,
    );
  }

  String? _extractMacOsUserHome(String? homePath) {
    if (homePath == null || homePath.trim().isEmpty) {
      return null;
    }

    final normalized = p.normalize(homePath);
    final match = RegExp(
      r'^(/Users/[^/]+)/Library/Containers/[^/]+/Data(?:/.*)?$',
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return match.group(1);
  }

  String _migrateSandboxedDocumentsPath(
    String resolvedPath, {
    required String homeDirectory,
  }) {
    if (!Platform.isMacOS) {
      return resolvedPath;
    }

    final normalizedHome = p.normalize(homeDirectory);
    final escapedHome = RegExp.escape(normalizedHome);
    final pattern = RegExp(
      '^$escapedHome/Library/Containers/[^/]+/Data/Documents(?:/(.*))?\$',
    );
    final match = pattern.firstMatch(resolvedPath);
    if (match == null) {
      return resolvedPath;
    }

    final suffix = match.group(1);
    return suffix == null || suffix.isEmpty
        ? p.join(normalizedHome, 'Documents')
        : p.join(normalizedHome, 'Documents', suffix);
  }

  String? _readEnv(String key) {
    final value = Platform.environment[key];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }
}

class _AppEmbeddedConfig {
  const _AppEmbeddedConfig._();

  // 단일 실행 파일 배포를 위해 운영 연결 정보를 앱 내부에 포함합니다.
  static const String apiBaseUrl = String.fromEnvironment(
    'SOFTEGG_API_BASE_URL',
    defaultValue: 'https://licensehub.ilycode.app',
  );
  static const String ftpHost = String.fromEnvironment(
    'SOFTEGG_FTP_HOST',
    defaultValue: 'ilysrv.ddns.net',
  );
  static const String ftpUser = String.fromEnvironment(
    'SOFTEGG_FTP_USER',
    defaultValue: 'asdf',
  );
  static const String ftpPassword = String.fromEnvironment(
    'SOFTEGG_FTP_PASSWORD',
    defaultValue: 'Emfndhk!',
  );
}
