import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:soft_egg_packager/src/data/catalog_api_client.dart';
import 'package:soft_egg_packager/src/data/catalog_repository.dart';
import 'package:soft_egg_packager/src/models/packaging_models.dart';
import 'package:soft_egg_packager/src/services/checksum_service.dart';
import 'package:soft_egg_packager/src/services/ftp_download_service.dart';
import 'package:soft_egg_packager/src/services/local_settings_service.dart';
import 'package:soft_egg_packager/src/services/package_builder_service.dart';
import 'package:soft_egg_packager/src/services/packaging_cancellation.dart';
import 'package:soft_egg_packager/src/theme/app_fonts.dart';

class PackagingWizardPage extends StatefulWidget {
  const PackagingWizardPage({super.key});

  @override
  State<PackagingWizardPage> createState() => _PackagingWizardPageState();
}

class _PackagingWizardPageState extends State<PackagingWizardPage> {
  static const double _headerHeight = 72;

  final List<TextEditingController> _partnerCodeControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _partnerCodeFocusNodes = List.generate(
    5,
    (_) => FocusNode(),
  );
  final LocalSettingsService _localSettingsService =
      const LocalSettingsService();
  final FtpDownloadService _ftpDownloadService = const FtpDownloadService();
  final ChecksumService _checksumService = const ChecksumService();
  final List<_LogLine> _logLines = <_LogLine>[];
  final List<_ToastNotice> _toastNotices = <_ToastNotice>[];
  final List<Timer> _toastTimers = <Timer>[];
  Timer? _completionAdvanceTimer;
  PackagingCancellationToken? _packagingCancellationToken;
  int _packagingSessionSeed = 0;
  int? _activePackagingSessionId;

  late final PackageBuilderService _packageBuilderService =
      PackageBuilderService(
        ftpDownloadService: _ftpDownloadService,
        checksumService: _checksumService,
      );

  int _currentStep = 0;
  String _partnerCode = '';
  bool _isSettingsLoading = true;
  bool _isCatalogLoading = false;
  bool _isCatalogServerChecking = false;
  bool _isPackagingRunning = false;
  bool _isStopRequested = false;
  double _packagingProgress = 0;
  String _currentTaskLabel = '대기 중';
  Duration _elapsed = Duration.zero;
  DateTime? _packagingStartedAt;
  int? _currentProcessedBytes;
  int? _currentTotalBytes;
  double? _currentBytesPerSecond;

  SoftEggSettings? _settings;
  String? _settingsError;
  String? _catalogServerError;
  DateTime? _catalogServerCheckedAt;
  CompanyCatalog? _catalog;
  List<SoftwareGroupViewModel> _softwareGroups = const [];
  SoftwareGroupViewModel? _selectedGroup;
  RemoteSoftwarePackage? _selectedPackage;
  Set<String> _selectedDependencyKeys = <String>{};
  final Map<String, int?> _remoteSizeCache = <String, int?>{};
  final Set<String> _remoteSizeLoadingKeys = <String>{};
  PackagingResult? _packagingResult;
  String? _catalogError;
  String? _packagingError;

  @override
  void initState() {
    super.initState();
    for (final controller in _partnerCodeControllers) {
      controller.addListener(_syncPartnerCode);
    }
    _loadSettings();
  }

  @override
  void dispose() {
    _completionAdvanceTimer?.cancel();
    for (final timer in _toastTimers) {
      timer.cancel();
    }
    for (final controller in _partnerCodeControllers) {
      controller.removeListener(_syncPartnerCode);
      controller.dispose();
    }
    for (final focusNode in _partnerCodeFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isSettingsLoading = true;
      _settingsError = null;
    });
    try {
      final settings = await _localSettingsService.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = settings;
        _isSettingsLoading = false;
      });
      unawaited(_probeCatalogServer(settings));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _settingsError = error.toString();
        _isSettingsLoading = false;
      });
      _showTopNotification(
        title: '런타임 초기화 실패',
        message: '앱 내장 런타임을 초기화하지 못했습니다. ${error.toString()}',
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFF59E0B),
      );
    }
  }

  Future<void> _probeCatalogServer(SoftEggSettings settings) async {
    setState(() {
      _isCatalogServerChecking = true;
      _catalogServerError = null;
    });
    try {
      await CatalogApiClient(baseUrl: settings.apiBaseUrl).probeServer();
      if (!mounted) {
        return;
      }
      setState(() {
        _isCatalogServerChecking = false;
        _catalogServerCheckedAt = DateTime.now();
      });
    } on CatalogException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCatalogServerChecking = false;
        _catalogServerError = error.message;
        _catalogServerCheckedAt = DateTime.now();
      });
      _appendLog('ERROR', '카탈로그 서버 상태 확인 실패: ${error.message}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCatalogServerChecking = false;
        _catalogServerError = '카탈로그 서버 상태를 확인하지 못했습니다.';
        _catalogServerCheckedAt = DateTime.now();
      });
      _appendLog('ERROR', '카탈로그 서버 상태 확인 실패: $error');
    }
  }

  void _syncPartnerCode() {
    final partnerCode = _partnerCodeControllers
        .map((controller) => controller.text.trim().toUpperCase())
        .join();
    if (_partnerCode == partnerCode) {
      return;
    }
    setState(() => _partnerCode = partnerCode);
  }

  KeyEventResult _handlePartnerCodeKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }

    final controller = _partnerCodeControllers[index];
    if (controller.text.isNotEmpty) {
      controller.clear();
      return KeyEventResult.handled;
    }

    if (index == 0) {
      return KeyEventResult.handled;
    }

    final previousController = _partnerCodeControllers[index - 1];
    previousController.clear();
    _partnerCodeFocusNodes[index - 1].requestFocus();
    return KeyEventResult.handled;
  }

  bool get _isPartnerCodeComplete {
    return _partnerCode.length == 5 &&
        RegExp(r'^[A-Z0-9]{5}$').hasMatch(_partnerCode);
  }

  List<RemoteSoftwareBinary> get _selectedDependencies {
    final selectedPackage = _selectedPackage;
    if (selectedPackage == null) {
      return const <RemoteSoftwareBinary>[];
    }
    return selectedPackage.dependencies
        .where((item) => _selectedDependencyKeys.contains(_dependencyKey(item)))
        .toList(growable: false);
  }

  bool get _canStartPackaging {
    final selectedPackage = _selectedPackage;
    if (selectedPackage == null) {
      return false;
    }
    if (_settings?.packagingBlocker != null) {
      return false;
    }
    if (!selectedPackage.mainBinary.hasUri) {
      return false;
    }
    return _selectedDependencies.every((item) => item.hasUri);
  }

  Future<void> _authorizePartnerCode() async {
    final settings = _settings;
    if (settings == null || !_isPartnerCodeComplete || _isCatalogLoading) {
      return;
    }

    setState(() {
      _isCatalogLoading = true;
      _catalogError = null;
    });

    try {
      final repository = CatalogRepository(
        apiClient: CatalogApiClient(baseUrl: settings.apiBaseUrl),
      );
      final catalog = await repository.fetchCatalog(_partnerCode);
      final groups = catalog.buildGroups();
      if (groups.isEmpty) {
        throw const CatalogException(
          message: '데스크톱 패키징 가능한 소프트웨어가 없습니다.',
          error: 'no_desktop_software',
          requestId: '',
          statusCode: 404,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _catalog = catalog;
        _softwareGroups = groups;
        _selectedGroup = groups.first;
        _selectedPackage = groups.first.packages.first;
        _selectedDependencyKeys = _selectedPackage!.dependencies
            .where((item) => item.hasUri)
            .map(_dependencyKey)
            .toSet();
        _currentStep = 1;
        _isCatalogLoading = false;
        _catalogServerError = null;
        _catalogServerCheckedAt = DateTime.now();
      });
      unawaited(_primeRemoteSizes());

      _appendLog(
        'INFO',
        '카탈로그 조회 완료: ${catalog.company.companyName} (${catalog.company.companyCode})',
      );
      _showTopNotification(
        title: '카탈로그 조회 완료',
        message:
            '${catalog.company.companyName}에 할당된 ${catalog.desktopPackages.length}개 패키지를 불러왔습니다.',
        icon: Icons.verified_rounded,
        accent: const Color(0xFF22C55E),
      );
    } on CatalogException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogError = error.message;
        _isCatalogLoading = false;
        if (error.error == 'network_error' ||
            error.error == 'timeout' ||
            error.error == 'tls_error') {
          _catalogServerError = error.message;
          _catalogServerCheckedAt = DateTime.now();
        }
      });
      _appendLog('ERROR', error.message);
      _showTopNotification(
        title: '카탈로그 조회 실패',
        message: error.message,
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFEF4444),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogError = '예상하지 못한 오류가 발생했습니다.';
        _isCatalogLoading = false;
      });
      _appendLog('ERROR', error.toString());
      _showTopNotification(
        title: '카탈로그 조회 실패',
        message: '예상하지 못한 오류가 발생했습니다.',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _startPackaging() async {
    final settings = _settings;
    final catalog = _catalog;
    final selectedPackage = _selectedPackage;
    if (settings == null ||
        catalog == null ||
        selectedPackage == null ||
        !_canStartPackaging ||
        _isPackagingRunning) {
      return;
    }

    _completionAdvanceTimer?.cancel();
    final cancellationToken = PackagingCancellationToken();
    final sessionId = ++_packagingSessionSeed;
    setState(() {
      _currentStep = 2;
      _isPackagingRunning = true;
      _isStopRequested = false;
      _packagingCancellationToken = cancellationToken;
      _activePackagingSessionId = sessionId;
      _packagingProgress = 0.01;
      _currentTaskLabel = '작업 시작';
      _packagingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      _currentProcessedBytes = null;
      _currentTotalBytes = null;
      _currentBytesPerSecond = null;
      _packagingResult = null;
      _packagingError = null;
      _logLines.clear();
    });

    _appendLog(
      'INFO',
      '패키징 시작: ${catalog.company.companyName} / ${selectedPackage.name} ${selectedPackage.version}',
    );
    _appendLog('INFO', '출력 경로: ${settings.exportRootPath}');
    if (_selectedDependencies.isEmpty) {
      _appendLog('INFO', '선택된 의존성 없음');
    } else {
      _appendLog('INFO', '선택 의존성 ${_selectedDependencies.length}개');
    }

    try {
      final result = await _packageBuilderService.build(
        settings: settings,
        company: catalog.company,
        softwarePackage: selectedPackage,
        selectedDependencies: _selectedDependencies,
        onProgress: (update) {
          if (!mounted || _activePackagingSessionId != sessionId) {
            return;
          }
          setState(() {
            _packagingProgress = update.progress;
            _currentTaskLabel = update.task;
            if (update.clearMetrics) {
              _currentProcessedBytes = null;
              _currentTotalBytes = null;
              _currentBytesPerSecond = null;
            } else {
              _currentProcessedBytes = update.processedBytes;
              _currentTotalBytes = update.totalBytes;
              _currentBytesPerSecond = update.bytesPerSecond;
            }
            final startedAt = _packagingStartedAt;
            if (startedAt != null) {
              _elapsed = DateTime.now().difference(startedAt);
            }
          });
          if (update.loggable) {
            _appendLog(update.level, update.message);
          }
        },
        cancellationToken: cancellationToken,
      );

      if (!mounted) {
        return;
      }
      if (_activePackagingSessionId != sessionId) {
        return;
      }
      setState(() {
        _packagingResult = result;
        _isPackagingRunning = false;
        _isStopRequested = false;
        _packagingCancellationToken = null;
        _activePackagingSessionId = null;
        _packagingProgress = 1;
        _currentTaskLabel = '패키징 완료';
        _currentProcessedBytes = null;
        _currentTotalBytes = null;
        _currentBytesPerSecond = null;
      });
      _scheduleCompletionAdvance();
      _showTopNotification(
        title: '패키징 완료',
        message: result.packageFileName,
        icon: Icons.inventory_2_rounded,
        accent: const Color(0xFF22C55E),
      );
    } on PackageBuildException catch (error) {
      if (!mounted) {
        return;
      }
      if (_activePackagingSessionId != sessionId &&
          error.message == '작업이 중단되었습니다.') {
        return;
      }
      final wasCancelled = error.message == '작업이 중단되었습니다.';
      setState(() {
        _currentStep = wasCancelled ? 1 : 2;
        _isPackagingRunning = false;
        _isStopRequested = false;
        _packagingCancellationToken = null;
        _activePackagingSessionId = null;
        _packagingError = wasCancelled ? null : error.message;
        _currentTaskLabel = wasCancelled ? '대기 중' : '패키징 실패';
        _packagingProgress = wasCancelled ? 0 : _packagingProgress;
        _packagingStartedAt = wasCancelled ? null : _packagingStartedAt;
        _elapsed = wasCancelled ? Duration.zero : _elapsed;
        _currentProcessedBytes = null;
        _currentTotalBytes = null;
        _currentBytesPerSecond = null;
        _packagingResult = wasCancelled ? null : _packagingResult;
      });
      _appendLog(wasCancelled ? 'WARN' : 'ERROR', error.message);
      _showTopNotification(
        title: wasCancelled ? '작업 중단' : '패키징 실패',
        message: error.message,
        icon: wasCancelled
            ? Icons.stop_circle_outlined
            : Icons.error_outline_rounded,
        accent: wasCancelled
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_activePackagingSessionId != sessionId) {
        return;
      }
      setState(() {
        _currentStep = 2;
        _isPackagingRunning = false;
        _isStopRequested = false;
        _packagingCancellationToken = null;
        _activePackagingSessionId = null;
        _packagingError = '패키징 중 예기치 않은 오류가 발생했습니다.';
        _currentTaskLabel = '패키징 실패';
        _currentProcessedBytes = null;
        _currentTotalBytes = null;
        _currentBytesPerSecond = null;
      });
      _appendLog('ERROR', error.toString());
      _showTopNotification(
        title: '패키징 실패',
        message: '패키징 중 예기치 않은 오류가 발생했습니다.',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFEF4444),
      );
    }
  }

  void _stopPackaging() {
    if (!_isPackagingRunning || _isStopRequested) {
      return;
    }
    _completionAdvanceTimer?.cancel();
    _packagingCancellationToken?.cancel();
    setState(() {
      _currentStep = 1;
      _activePackagingSessionId = null;
      _isPackagingRunning = false;
      _isStopRequested = false;
      _packagingCancellationToken = null;
      _packagingProgress = 0;
      _currentTaskLabel = '대기 중';
      _packagingStartedAt = null;
      _elapsed = Duration.zero;
      _currentProcessedBytes = null;
      _currentTotalBytes = null;
      _currentBytesPerSecond = null;
      _packagingError = null;
      _packagingResult = null;
      _logLines.clear();
    });
    _showTopNotification(
      title: '작업 중단',
      message: '현재 작업을 중단하고 이전 단계로 이동했습니다.',
      icon: Icons.stop_circle_outlined,
      accent: const Color(0xFFF59E0B),
    );
  }

  void _appendLog(String level, String message) {
    if (_logLines.isNotEmpty &&
        _logLines.first.level == level &&
        _logLines.first.message == message) {
      return;
    }
    setState(() {
      _logLines.insert(
        0,
        _LogLine(timestamp: DateTime.now(), level: level, message: message),
      );
    });
  }

  void _onSelectSoftwareGroup(String groupId) {
    final nextGroup = _softwareGroups.firstWhere(
      (item) => item.id == groupId,
      orElse: () => _softwareGroups.first,
    );
    setState(() {
      _selectedGroup = nextGroup;
      _selectedPackage = nextGroup.packages.first;
      _selectedDependencyKeys = _selectedPackage!.dependencies
          .where((item) => item.hasUri)
          .map(_dependencyKey)
          .toSet();
      _packagingError = null;
    });
    unawaited(_primeRemoteSizes());
  }

  void _onSelectVersion(String packageId) {
    final selectedGroup = _selectedGroup;
    if (selectedGroup == null) {
      return;
    }
    final nextPackage = selectedGroup.packages.firstWhere(
      (item) => item.id == packageId,
      orElse: () => selectedGroup.packages.first,
    );
    setState(() {
      _selectedPackage = nextPackage;
      _selectedDependencyKeys = nextPackage.dependencies
          .where((item) => item.hasUri)
          .map(_dependencyKey)
          .toSet();
      _packagingError = null;
    });
    unawaited(_primeRemoteSizes());
  }

  void _toggleDependency(String key, bool enabled) {
    setState(() {
      if (enabled) {
        _selectedDependencyKeys.add(key);
      } else {
        _selectedDependencyKeys.remove(key);
      }
    });
  }

  String _dependencyKey(RemoteSoftwareBinary binary) {
    return '${binary.uri}|${binary.name}|${binary.version}';
  }

  Future<void> _primeRemoteSizes() async {
    final settings = _settings;
    final selectedPackage = _selectedPackage;
    if (settings == null ||
        selectedPackage == null ||
        !settings.hasFtpCredentials) {
      return;
    }

    final binaries = <RemoteSoftwareBinary>[
      selectedPackage.mainBinary,
      ...selectedPackage.dependencies,
    ].where((item) => item.hasUri);

    for (final binary in binaries) {
      final uri = binary.uri.trim();
      if (uri.isEmpty ||
          _remoteSizeCache.containsKey(uri) ||
          _remoteSizeLoadingKeys.contains(uri)) {
        continue;
      }
      setState(() => _remoteSizeLoadingKeys.add(uri));
      try {
        final size = await _ftpDownloadService.fetchRemoteSize(
          ftpUri: uri,
          settings: settings,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _remoteSizeCache[uri] = size;
          _remoteSizeLoadingKeys.remove(uri);
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _remoteSizeCache[uri] = null;
          _remoteSizeLoadingKeys.remove(uri);
        });
      }
    }
  }

  Future<void> _refreshRemoteSizes() async {
    final selectedPackage = _selectedPackage;
    if (selectedPackage == null) {
      return;
    }
    final uris = <String>{
      if (selectedPackage.mainBinary.hasUri)
        selectedPackage.mainBinary.uri.trim(),
      ...selectedPackage.dependencies
          .where((item) => item.hasUri)
          .map((item) => item.uri.trim()),
    };
    setState(() {
      for (final uri in uris) {
        _remoteSizeCache.remove(uri);
        _remoteSizeLoadingKeys.remove(uri);
      }
    });
    await _primeRemoteSizes();
  }

  void _resetWizard() {
    if (_isPackagingRunning) {
      _showTopNotification(
        title: '작업 진행 중',
        message: '실행 중인 패키징이 끝난 뒤 다시 시도해 주십시오.',
        icon: Icons.timer_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }
    _completionAdvanceTimer?.cancel();
    for (final controller in _partnerCodeControllers) {
      controller.clear();
    }
    setState(() {
      _currentStep = 0;
      _partnerCode = '';
      _catalog = null;
      _softwareGroups = const [];
      _selectedGroup = null;
      _selectedPackage = null;
      _selectedDependencyKeys = <String>{};
      _remoteSizeCache.clear();
      _remoteSizeLoadingKeys.clear();
      _packagingCancellationToken = null;
      _activePackagingSessionId = null;
      _isStopRequested = false;
      _packagingProgress = 0;
      _currentTaskLabel = '대기 중';
      _packagingStartedAt = null;
      _elapsed = Duration.zero;
      _currentProcessedBytes = null;
      _currentTotalBytes = null;
      _currentBytesPerSecond = null;
      _catalogError = null;
      _packagingError = null;
      _packagingResult = null;
      _logLines.clear();
    });
    if (mounted) {
      _partnerCodeFocusNodes.first.requestFocus();
    }
  }

  void _goToPreviousStep() {
    if (_isPackagingRunning) {
      return;
    }
    _completionAdvanceTimer?.cancel();
    if (_currentStep == 1) {
      setState(() {
        _currentStep = 0;
        _catalogError = null;
        _packagingError = null;
      });
      return;
    }
    if (_currentStep == 2) {
      setState(() {
        _currentStep = 1;
        _packagingCancellationToken = null;
        _activePackagingSessionId = null;
        _isStopRequested = false;
        _packagingProgress = 0;
        _currentTaskLabel = '대기 중';
        _packagingStartedAt = null;
        _elapsed = Duration.zero;
        _currentProcessedBytes = null;
        _currentTotalBytes = null;
        _currentBytesPerSecond = null;
        _packagingError = null;
        _packagingResult = null;
        _logLines.clear();
      });
    }
  }

  void _startNewPackageFromCurrentAccess() {
    if (_isPackagingRunning) {
      return;
    }
    _completionAdvanceTimer?.cancel();
    setState(() {
      _currentStep = 1;
      _packagingCancellationToken = null;
      _activePackagingSessionId = null;
      _isStopRequested = false;
      _packagingProgress = 0;
      _currentTaskLabel = '대기 중';
      _packagingStartedAt = null;
      _elapsed = Duration.zero;
      _currentProcessedBytes = null;
      _currentTotalBytes = null;
      _currentBytesPerSecond = null;
      _packagingError = null;
      _packagingResult = null;
      _logLines.clear();
    });
  }

  void _scheduleCompletionAdvance() {
    _completionAdvanceTimer?.cancel();
    _completionAdvanceTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _packagingResult == null || _packagingError != null) {
        return;
      }
      setState(() {
        _currentStep = 3;
      });
    });
  }

  Future<void> _copyExportPath() async {
    final path = _packagingResult?.packageFilePath;
    if (path == null || path.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    _showTopNotification(
      title: '경로 복사 완료',
      message: path,
      icon: Icons.content_copy_rounded,
      accent: const Color(0xFF22C55E),
    );
  }

  Future<void> _copyLogs() async {
    if (_logLines.isEmpty) {
      return;
    }
    final payload = _logLines.reversed
        .map((item) => item.asPlainText)
        .join('\n');
    await Clipboard.setData(ClipboardData(text: payload));
    _showTopNotification(
      title: '로그 복사 완료',
      message: '로그 ${_logLines.length}줄을 클립보드에 복사했습니다.',
      icon: Icons.content_copy_rounded,
      accent: const Color(0xFF22C55E),
    );
  }

  Future<void> _saveLogs() async {
    final settings = _settings;
    if (settings == null || _logLines.isEmpty) {
      return;
    }
    final directory = Directory(settings.exportRootPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final formatter = DateFormat('yyyyMMdd_HHmmss');
    final file = File(
      p.join(
        directory.path,
        'softegg-log-${formatter.format(DateTime.now())}.txt',
      ),
    );
    final payload = _logLines.reversed
        .map((item) => item.asPlainText)
        .join('\n');
    await file.writeAsString(payload);
    _showTopNotification(
      title: '로그 저장 완료',
      message: file.path,
      icon: Icons.save_alt_rounded,
      accent: const Color(0xFF60A5FA),
    );
  }

  Future<void> _openExportFolder() async {
    final packagePath = _packagingResult?.packageFilePath;
    if (packagePath == null || packagePath.isEmpty) {
      return;
    }
    try {
      if (Platform.isMacOS) {
        await Process.start('open', ['-R', packagePath]);
      } else if (Platform.isWindows) {
        final normalized = packagePath.replaceAll('/', r'\');
        await Process.start('explorer', ['/select,$normalized']);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [p.dirname(packagePath)]);
      }
    } catch (_) {
      _showTopNotification(
        title: '폴더 열기 실패',
        message: '폴더를 자동으로 열지 못했습니다. 경로 복사를 사용해 주십시오.',
        icon: Icons.folder_off_outlined,
        accent: const Color(0xFFF59E0B),
      );
    }
  }

  Future<void> _editExportRoot() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    final nextPath = await getDirectoryPath(
      initialDirectory: settings.exportRootPath,
      confirmButtonText: 'Select Export Folder',
    );
    if (!mounted || nextPath == null) {
      return;
    }

    try {
      final updatedSettings = await _localSettingsService.updateExportRoot(
        nextPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = updatedSettings;
        _packagingResult = null;
        _packagingError = null;
      });
      _showTopNotification(
        title: 'Export Root 적용 완료',
        message: _displayPath(updatedSettings.exportRootPath),
        icon: Icons.folder_rounded,
        accent: const Color(0xFF22C55E),
      );
    } on FormatException catch (error) {
      _showTopNotification(
        title: 'Export Root 변경 실패',
        message: error.message,
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFF59E0B),
      );
    } catch (error) {
      _showTopNotification(
        title: 'Export Root 변경 실패',
        message: error.toString(),
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFF59E0B),
      );
    }
  }

  String _displayPath(String? rawPath) {
    if (rawPath == null || rawPath.isEmpty) {
      return '-';
    }

    final homeDirectory = _localSettingsService.resolveHomeDirectory();
    if (homeDirectory.isNotEmpty) {
      final normalizedHome = p.normalize(homeDirectory);
      final normalizedPath = p.normalize(rawPath);
      if (normalizedPath == normalizedHome) {
        return '~';
      }
      if (p.isWithin(normalizedHome, normalizedPath)) {
        final relative = p.relative(normalizedPath, from: normalizedHome);
        return p.join('~', relative);
      }
    }

    return rawPath;
  }

  String _presentTaskLabel(String rawTask) {
    if (rawTask.contains('메인 바이너리')) {
      if (rawTask.contains('재연결')) {
        return '주요 파일 준비를 다시 시도하는 중';
      }
      if (rawTask.contains('체크섬')) {
        return '주요 파일 확인 중';
      }
      if (rawTask.contains('완료')) {
        return '주요 파일 준비 완료';
      }
      return '주요 파일 준비 중';
    }
    if (rawTask.contains('의존성')) {
      if (rawTask == '의존성 없음') {
        return '추가 구성 요소 없음';
      }
      if (rawTask.contains('재연결')) {
        return '추가 구성 요소 준비를 다시 시도하는 중';
      }
      if (rawTask.contains('체크섬')) {
        return '추가 구성 요소 확인 중';
      }
      if (rawTask.contains('완료')) {
        return '추가 구성 요소 준비 완료';
      }
      return '추가 구성 요소 준비 중';
    }
    if (rawTask.contains('매니페스트')) {
      return '패키지 정보 정리 중';
    }
    if (rawTask.contains('.segg')) {
      return '패키지 파일 정리 중';
    }
    if (rawTask.contains('패키지 배치')) {
      return '저장 위치에 패키지 배치 중';
    }
    if (rawTask.contains('원격 파일 정보 확인')) {
      return '필요한 파일 정보 확인 중';
    }
    if (rawTask.contains('작업 디렉터리 준비')) {
      return '작업 준비 중';
    }
    if (rawTask.contains('패키징 완료')) {
      return '패키지 생성 완료';
    }
    return rawTask;
  }

  String _presentLogMessage(String rawMessage) {
    if (rawMessage.contains('다운로드를 시작합니다')) {
      return '필요한 파일을 준비하고 있습니다.';
    }
    if (rawMessage.contains('체크섬을 검증합니다')) {
      return '준비한 파일을 확인하고 있습니다.';
    }
    if (rawMessage.contains('다운로드 및 검증이 완료되었습니다')) {
      return '파일 준비가 완료되었습니다.';
    }
    if (rawMessage.contains('선택된 의존성이 없어 다음 단계로 진행합니다')) {
      return '추가로 준비할 항목이 없어 다음 단계로 진행합니다.';
    }
    if (rawMessage.contains('패키지 내부 매니페스트를 작성합니다')) {
      return '패키지 정보를 정리하고 있습니다.';
    }
    if (rawMessage.contains('압축 아카이브를 생성합니다')) {
      return '패키지 파일을 만들고 있습니다.';
    }
    if (rawMessage.contains('아카이브 구성')) {
      return '패키지 파일을 정리하고 있습니다.';
    }
    if (rawMessage.contains('원격 크기를 확인합니다')) {
      return '필요한 파일 정보를 확인하고 있습니다.';
    }
    if (rawMessage.contains('FTP 다운로드에 실패했습니다')) {
      return '파일 준비 중 연결 문제가 발생했습니다.';
    }
    if (rawMessage.contains('연결을 다시 시도합니다')) {
      return '연결을 다시 시도하고 있습니다.';
    }
    return rawMessage
        .replaceAll('메인 바이너리', '주요 파일')
        .replaceAll('의존성', '추가 구성 요소')
        .replaceAll('체크섬', '확인')
        .replaceAll('매니페스트', '패키지 정보')
        .replaceAll('.segg', '패키지 파일')
        .replaceAll('FTP', '')
        .trim();
  }

  void _showTopNotification({
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color accent = const Color(0xFF60A5FA),
  }) {
    final notice = _ToastNotice(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_toastNotices.length}',
      title: title,
      message: message,
      icon: icon,
      accent: accent,
    );
    setState(() => _toastNotices.add(notice));

    late final Timer hideTimer;
    hideTimer = Timer(const Duration(milliseconds: 2600), () {
      _toastTimers.remove(hideTimer);
      if (!mounted) {
        return;
      }
      final index = _toastNotices.indexWhere((item) => item.id == notice.id);
      if (index == -1) {
        return;
      }
      setState(() => _toastNotices[index].visible = false);
    });

    late final Timer removeTimer;
    removeTimer = Timer(const Duration(milliseconds: 3000), () {
      _toastTimers.remove(removeTimer);
      if (!mounted) {
        return;
      }
      setState(() => _toastNotices.removeWhere((item) => item.id == notice.id));
    });

    _toastTimers.add(hideTimer);
    _toastTimers.add(removeTimer);
  }

  @override
  Widget build(BuildContext context) {
    const stepMeta = <_StepMeta>[
      _StepMeta(index: 0, label: 'Step 1', detail: 'Partner Access'),
      _StepMeta(index: 1, label: 'Step 2', detail: 'Configuration'),
      _StepMeta(index: 2, label: 'Step 3', detail: 'Packaging'),
      _StepMeta(index: 3, label: 'Step 4', detail: 'Completion'),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                _buildStepper(stepMeta),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: KeyedSubtree(
                      key: ValueKey(_currentStep),
                      child: _buildMainBody(),
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
            if (_toastNotices.isNotEmpty) _buildNotificationOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final showHeaderMeta = _currentStep != 0;
    final companyName = _catalog?.company.companyName.trim() ?? '';
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF2563EB).withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(Icons.layers_rounded, color: Color(0xFF60A5FA)),
          ),
          const SizedBox(width: 12),
          Text(
            'SoftEgg',
            style: AppFonts.lexend(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 18),
          _badge(
            label: _isSettingsLoading
                ? '초기화 중'
                : _settingsError == null
                ? 'LIVE READY'
                : 'RUNTIME ERROR',
            color: _isSettingsLoading
                ? const Color(0xFF60A5FA)
                : _settingsError == null
                ? const Color(0xFF22C55E)
                : const Color(0xFFEF4444),
          ),
          if (showHeaderMeta) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.business_rounded,
                    size: 16,
                    color: Color(0xFF60A5FA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    companyName.isEmpty ? '파트너 미선택' : companyName,
                    style: AppFonts.sourceSans3(
                      color: const Color(0xFFE2E8F0),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepper(List<_StepMeta> steps) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: Color(0xFF1F2937))),
        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              _buildStepPill(steps[i]),
              if (i < steps.length - 1)
                Container(
                  width: 32,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: const Color(0xFF334155),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepPill(_StepMeta meta) {
    final isDone = meta.index < _currentStep;
    final isCurrent = meta.index == _currentStep;
    final textColor = isCurrent
        ? const Color(0xFF60A5FA)
        : isDone
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF64748B);
    return Row(
      children: [
        if (isDone)
          const Icon(Icons.task_alt_rounded, size: 18, color: Color(0xFF22C55E))
        else
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFF2563EB) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF475569),
              ),
            ),
            child: Text(
              '${meta.index + 1}',
              style: AppFonts.sourceSans3(
                fontWeight: FontWeight.w700,
                color: isCurrent ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 11,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          meta.label,
          style: AppFonts.sourceSans3(
            color: textColor,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildMainBody() {
    switch (_currentStep) {
      case 0:
        return _buildPartnerCodeStep();
      case 1:
        return _buildConfigurationStep();
      case 2:
        return _buildPackagingStep();
      case 3:
        return _buildCompletionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPartnerCodeStep() {
    final settings = _settings;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E293B)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF38BDF8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SECURE TERMINAL',
                        style: AppFonts.sourceSans3(
                          color: const Color(0xFF93C5FD),
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Partner Access Gateway',
                  textAlign: TextAlign.center,
                  style: AppFonts.jetBrainsMono(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '5자리 회사 코드를 입력하면 실제 운영 카탈로그를 조회합니다.',
                  style: AppFonts.sourceSans3(
                    color: const Color(0xFF94A3B8),
                    fontSize: 16,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: List.generate(5, (index) {
                    return SizedBox(
                      width: 58,
                      child: Focus(
                        onKeyEvent: (_, event) =>
                            _handlePartnerCodeKey(index, event),
                        child: TextField(
                          controller: _partnerCodeControllers[index],
                          focusNode: _partnerCodeFocusNodes[index],
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.characters,
                          style: AppFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF111827),
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF3B82F6),
                                width: 1.6,
                              ),
                            ),
                          ),
                          maxLength: 1,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(1),
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9]'),
                            ),
                          ],
                          onChanged: (value) {
                            final upper = value.toUpperCase();
                            if (value != upper) {
                              _partnerCodeControllers[index].value =
                                  TextEditingValue(
                                    text: upper,
                                    selection: TextSelection.collapsed(
                                      offset: upper.length,
                                    ),
                                  );
                            }
                            if (upper.isNotEmpty &&
                                index < _partnerCodeFocusNodes.length - 1) {
                              _partnerCodeFocusNodes[index + 1].requestFocus();
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                if (_partnerCode.isNotEmpty)
                  Text(
                    '입력 코드: ${_partnerCode.padRight(5, '•')}',
                    style: AppFonts.sourceSans3(
                      color: _isPartnerCodeComplete
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 24),
                _buildRuntimeStatusConsole(settings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuntimeStatusConsole(SoftEggSettings? settings) {
    final runtimeOk = !_isSettingsLoading && _settingsError == null;
    final catalogOk =
        !_isSettingsLoading &&
        !_isCatalogServerChecking &&
        _catalogServerError == null;
    final checkedAt = _catalogServerCheckedAt;
    final checkedAtLabel = checkedAt == null
        ? '대기 중'
        : DateFormat('HH:mm:ss').format(checkedAt);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1220),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                _terminalDot(const Color(0xFFEF4444)),
                const SizedBox(width: 8),
                _terminalDot(const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                _terminalDot(const Color(0xFF22C55E)),
                const SizedBox(width: 14),
                Text(
                  'runtime-status.console',
                  style: AppFonts.jetBrainsMono(
                    color: const Color(0xFF93C5FD),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _isSettingsLoading || settings == null
                      ? null
                      : () => _probeCatalogServer(settings),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    _isCatalogServerChecking ? 'Checking' : 'Retry Probe',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _runtimeConsoleLine(
                  prompt: r'$',
                  command: 'boot.runtime --embedded',
                  status: runtimeOk
                      ? 'OK'
                      : (_isSettingsLoading ? 'WAIT' : 'ERR'),
                  statusColor: runtimeOk
                      ? const Color(0xFF22C55E)
                      : _isSettingsLoading
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFFEF4444),
                ),
                const SizedBox(height: 10),
                _runtimeConsoleLine(
                  prompt: '>',
                  command: 'check.catalog --health',
                  status: _isCatalogServerChecking
                      ? 'RUN'
                      : catalogOk
                      ? 'LIVE'
                      : 'FAIL',
                  statusColor: _isCatalogServerChecking
                      ? const Color(0xFF38BDF8)
                      : catalogOk
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                ),
                const SizedBox(height: 14),
                _runtimeConsoleMeta(
                  label: 'engine',
                  value: runtimeOk
                      ? 'embedded runtime ready'
                      : _settingsError ?? 'initializing runtime',
                ),
                _runtimeConsoleMeta(
                  label: 'catalog',
                  value: _isCatalogServerChecking
                      ? 'health probe running'
                      : _catalogServerError ??
                            'licensehub.ilycode.app reachable',
                  valueColor: _catalogServerError == null
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFFFCA5A5),
                ),
                _runtimeConsoleMeta(label: 'checked_at', value: checkedAtLabel),
                _runtimeConsoleMeta(
                  label: 'export_root',
                  value: _displayPath(settings?.exportRootPath),
                ),
                _runtimeConsoleMeta(
                  label: 'input_mode',
                  value: '5-char partner code / backspace rewrite enabled',
                ),
                if (_catalogError != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F1D1D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7F1D1D)),
                    ),
                    child: Text(
                      _catalogError!,
                      style: AppFonts.jetBrainsMono(
                        color: const Color(0xFFFCA5A5),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _terminalDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _runtimeConsoleLine({
    required String prompt,
    required String command,
    required String status,
    required Color statusColor,
  }) {
    return Row(
      children: [
        Text(
          prompt,
          style: AppFonts.jetBrainsMono(
            color: const Color(0xFF22C55E),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            command,
            style: AppFonts.jetBrainsMono(
              color: const Color(0xFFE2E8F0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            status,
            style: AppFonts.jetBrainsMono(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _runtimeConsoleMeta({
    required String label,
    required String value,
    Color valueColor = const Color(0xFFE2E8F0),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: label.padRight(11),
              style: AppFonts.jetBrainsMono(
                color: const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: ' : ',
              style: AppFonts.jetBrainsMono(
                color: const Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: AppFonts.jetBrainsMono(
                color: valueColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationStep() {
    final catalog = _catalog;
    final selectedGroup = _selectedGroup;
    final selectedPackage = _selectedPackage;
    if (catalog == null || selectedGroup == null || selectedPackage == null) {
      return Center(
        child: Text(
          '카탈로그 데이터가 없습니다.',
          style: AppFonts.sourceSans3(color: Colors.white, fontSize: 18),
        ),
      );
    }

    final settingsBlocker = _settings?.packagingBlocker;
    final desktopShortcuts = selectedPackage.installOptions.desktopShortcuts;
    final startupPrograms = selectedPackage.installOptions.startupPrograms;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1080;
          final mainArea = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Partner Package Configuration',
                style: AppFonts.lexend(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${catalog.company.companyName}에 할당된 운영 패키지 중 하나를 선택합니다.',
                style: AppFonts.sourceSans3(
                  color: const Color(0xFF94A3B8),
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 18),
              _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPanelTitle(
                          Icons.settings_applications_outlined,
                          'Core Software Selection',
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _badge(
                                label: selectedPackage.os.toUpperCase(),
                                color: const Color(0xFF2563EB),
                              ),
                              _badge(
                                label: selectedPackage.releaseChannel
                                    .toUpperCase(),
                                color: const Color(0xFF0EA5E9),
                              ),
                              _badge(
                                label: _packageAvailabilityLabel(
                                  selectedPackage,
                                ),
                                color: _packageAvailabilityColor(
                                  selectedPackage,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: 360,
                          child: ButtonTheme(
                            alignedDropdown: true,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('group-${selectedGroup.id}'),
                              initialValue: selectedGroup.id,
                              decoration: _inputDecoration('Software Group'),
                              dropdownColor: const Color(0xFF162235),
                              style: AppFonts.sourceSans3(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                              iconEnabledColor: const Color(0xFFBFDBFE),
                              isExpanded: true,
                              isDense: false,
                              itemHeight: 52,
                              menuMaxHeight: 320,
                              borderRadius: BorderRadius.circular(14),
                              selectedItemBuilder: (context) {
                                return _softwareGroups
                                    .map(
                                      (group) =>
                                          _buildGroupDropdownLabel(group),
                                    )
                                    .toList(growable: false);
                              },
                              items: [
                                for (final group in _softwareGroups)
                                  DropdownMenuItem(
                                    value: group.id,
                                    child: _buildGroupDropdownLabel(group),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  _onSelectSoftwareGroup(value);
                                }
                              },
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: ButtonTheme(
                            alignedDropdown: true,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('version-${selectedPackage.id}'),
                              initialValue: selectedPackage.id,
                              decoration: _inputDecoration('Version'),
                              dropdownColor: const Color(0xFF162235),
                              style: AppFonts.jetBrainsMono(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                              iconEnabledColor: const Color(0xFFBFDBFE),
                              isExpanded: true,
                              isDense: false,
                              itemHeight: 50,
                              menuMaxHeight: 280,
                              borderRadius: BorderRadius.circular(14),
                              selectedItemBuilder: (context) {
                                return selectedGroup.packages
                                    .map(
                                      (version) =>
                                          _buildVersionDropdownLabel(version),
                                    )
                                    .toList(growable: false);
                              },
                              items: [
                                for (final version in selectedGroup.packages)
                                  DropdownMenuItem(
                                    value: version.id,
                                    child: _buildVersionDropdownLabel(version),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  _onSelectVersion(value);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildPanelTitle(
                          Icons.cloud_download_outlined,
                          'Main Binary',
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _settings?.hasFtpCredentials == true
                              ? _refreshRemoteSizes
                              : null,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Size Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        title: Text(
                          selectedPackage.mainBinary.fileName,
                          style: AppFonts.sourceSans3(
                            color: const Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '버전 ${selectedPackage.mainBinary.version.isEmpty ? selectedPackage.version : selectedPackage.mainBinary.version} • ${_remoteSizeLabel(selectedPackage.mainBinary)} • ${selectedPackage.mainBinary.checksum.isEmpty ? "체크섬 미등록" : selectedPackage.mainBinary.checksum}',
                          style: AppFonts.sourceSans3(
                            color: selectedPackage.mainBinary.hasUri
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFFFCA5A5),
                          ),
                        ),
                        trailing: selectedPackage.mainBinary.hasUri
                            ? const Icon(
                                Icons.check_circle_outline_rounded,
                                color: Color(0xFF22C55E),
                              )
                            : const Icon(
                                Icons.block_rounded,
                                color: Color(0xFFEF4444),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPanelTitle(
                      Icons.account_tree_outlined,
                      'Dependencies',
                    ),
                    const SizedBox(height: 12),
                    if (selectedPackage.dependencies.isEmpty)
                      Text(
                        '선택된 의존성이 없습니다.',
                        style: AppFonts.sourceSans3(
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    for (final dependency in selectedPackage.dependencies)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1220),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: CheckboxListTile(
                          value: _selectedDependencyKeys.contains(
                            _dependencyKey(dependency),
                          ),
                          activeColor: const Color(0xFF2563EB),
                          checkColor: Colors.white,
                          title: Text(
                            dependency.fileName,
                            style: AppFonts.sourceSans3(
                              color: const Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '버전 ${dependency.version.isEmpty ? "-" : dependency.version} • ${_remoteSizeLabel(dependency)} • ${dependency.checksum.isEmpty ? "체크섬 미등록" : dependency.checksum}',
                            style: AppFonts.sourceSans3(
                              color: dependency.hasUri
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFFFCA5A5),
                            ),
                          ),
                          secondary: dependency.hasUri
                              ? const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: Color(0xFF22C55E),
                                )
                              : const Icon(
                                  Icons.block_rounded,
                                  color: Color(0xFFEF4444),
                                ),
                          onChanged: dependency.hasUri
                              ? (checked) => _toggleDependency(
                                  _dependencyKey(dependency),
                                  checked ?? false,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPanelTitle(
                      Icons.playlist_add_check_rounded,
                      'Install Options',
                    ),
                    const SizedBox(height: 12),
                    _buildInstallOptionSection(
                      title: 'Desktop Shortcuts',
                      entries: desktopShortcuts,
                      legacyTargets:
                          selectedPackage.installOptions.desktopShortcutTargets,
                    ),
                    const SizedBox(height: 14),
                    _buildInstallOptionSection(
                      title: 'Startup Programs',
                      entries: startupPrograms,
                      legacyTargets:
                          selectedPackage.installOptions.startupTargets,
                    ),
                  ],
                ),
              ),
            ],
          );

          final sideArea = _buildPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildPanelTitle(
                      Icons.folder_open_rounded,
                      'Export Destination',
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _editExportRoot,
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _summaryLine(
                  'Current Root',
                  _displayPath(_settings?.exportRootPath),
                ),
                const SizedBox(height: 16),
                _buildPanelTitle(Icons.analytics_outlined, 'Current Snapshot'),
                const SizedBox(height: 14),
                _summaryLine(
                  'Partner',
                  '${catalog.company.companyName} (${catalog.company.companyCode})',
                ),
                _summaryLine(
                  'Product',
                  '${selectedPackage.name} ${selectedPackage.version}',
                ),
                _summaryLine('Code Name', selectedPackage.codeName),
                _summaryLine(
                  'Selected Dependencies',
                  '${_selectedDependencies.length}/${selectedPackage.dependencies.length}',
                ),
                _summaryLine('Estimated Payload', _estimatedPayloadLabel()),
                _summaryLine('Packagable', _canStartPackaging ? 'Yes' : 'No'),
                const SizedBox(height: 14),
                if (settingsBlocker != null)
                  _warningCard(settingsBlocker)
                else if (!selectedPackage.mainBinary.hasUri)
                  _warningCard('메인 바이너리 URI가 없어 패키징을 시작할 수 없습니다.')
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'Start Packaging을 누르면 선택한 구성으로 패키지 생성을 시작합니다.',
                      style: AppFonts.sourceSans3(
                        color: const Color(0xFFBFDBFE),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          );

          if (!isWide) {
            return SingleChildScrollView(
              child: Column(
                children: [mainArea, const SizedBox(height: 18), sideArea],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: SingleChildScrollView(child: mainArea)),
              const SizedBox(width: 18),
              Expanded(flex: 2, child: sideArea),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInstallOptionSection({
    required String title,
    required List<RemoteInstallEntry> entries,
    required List<String> legacyTargets,
  }) {
    final hasEntries = entries.isNotEmpty || legacyTargets.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppFonts.sourceSans3(
            color: const Color(0xFF93C5FD),
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        if (!hasEntries)
          Text(
            '설정된 항목이 없습니다.',
            style: AppFonts.sourceSans3(color: const Color(0xFF94A3B8)),
          ),
        for (final entry in entries)
          _installOptionTile(entry.displayName, entry.target),
        for (final target in legacyTargets) _installOptionTile(target, target),
      ],
    );
  }

  Widget _installOptionTile(String title, String target) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.subdirectory_arrow_right_rounded,
            color: Color(0xFF60A5FA),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.sourceSans3(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (target.trim().isNotEmpty)
                  Text(
                    target,
                    style: AppFonts.jetBrainsMono(
                      color: const Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagingStep() {
    final percent = (_packagingProgress * 100).round();
    final startedAt = _packagingStartedAt;
    final elapsed = startedAt == null
        ? _elapsed
        : DateTime.now().difference(startedAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Packaging Application',
                style: AppFonts.lexend(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '선택한 구성으로 패키지 파일을 준비하고 저장하는 단계입니다.',
                style: AppFonts.sourceSans3(
                  color: const Color(0xFF94A3B8),
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 20),
              _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Task',
                                style: AppFonts.sourceSans3(
                                  color: const Color(0xFF60A5FA),
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _presentTaskLabel(_currentTaskLabel),
                                style: AppFonts.sourceSans3(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_packagingError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _packagingError!,
                                  style: AppFonts.sourceSans3(
                                    color: const Color(0xFFFCA5A5),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          '$percent%',
                          style: AppFonts.lexend(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 12,
                        value: _packagingProgress,
                        backgroundColor: const Color(0xFF1E293B),
                        color: _packagingError == null
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _statusChip(
                          label: '파일 준비',
                          done:
                              _packagingProgress >= 0.90 &&
                              !_currentTaskLabel.contains('다운로드'),
                          inProgress: _currentTaskLabel.contains('다운로드'),
                        ),
                        _statusChip(
                          label: '내용 확인',
                          done:
                              _packagingProgress >= 0.97 &&
                              !_currentTaskLabel.contains('체크섬'),
                          inProgress: _currentTaskLabel.contains('체크섬'),
                        ),
                        _statusChip(
                          label: '패키지 정리',
                          done: _packagingResult != null,
                          inProgress:
                              _currentTaskLabel.contains('매니페스트') ||
                              _currentTaskLabel.contains('.segg'),
                        ),
                        _statusChip(
                          label: '진행 시간: ${elapsed.inSeconds}s',
                          done: false,
                          inProgress: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 980;
                  final stagePanel = _buildPackagingStagesPanel();
                  final telemetryPanel = _buildPackagingTelemetryPanel();
                  if (!isWide) {
                    return Column(
                      children: [
                        stagePanel,
                        const SizedBox(height: 18),
                        telemetryPanel,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: stagePanel),
                      const SizedBox(width: 18),
                      Expanded(child: telemetryPanel),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildPanelTitle(Icons.terminal_rounded, '작업 내역'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _logLines.isEmpty ? null : _copyLogs,
                          icon: const Icon(
                            Icons.content_copy_rounded,
                            size: 16,
                          ),
                          label: const Text('Copy'),
                        ),
                        TextButton.icon(
                          onPressed: _logLines.isEmpty ? null : _saveLogs,
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 260),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070B13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: _logLines.isEmpty
                          ? Text(
                              '패키지 생성을 시작하면 진행 내역이 표시됩니다.',
                              style: AppFonts.jetBrainsMono(
                                color: const Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final log in _logLines.take(20))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '[${log.timeText}] ',
                                            style: AppFonts.jetBrainsMono(
                                              color: const Color(0xFF475569),
                                              fontSize: 12,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '${log.level} ',
                                            style: AppFonts.jetBrainsMono(
                                              color: _logColor(log.level),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(
                                            text: _presentLogMessage(
                                              log.message,
                                            ),
                                            style: AppFonts.jetBrainsMono(
                                              color: const Color(0xFFCBD5E1),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackagingStagesPanel() {
    final progress = _packagingProgress;
    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelTitle(Icons.alt_route_rounded, '진행 단계'),
          const SizedBox(height: 12),
          _stageTile(
            title: '1. 주요 파일 준비',
            subtitle: '기본 파일을 준비합니다',
            state: _resolveTaskDrivenStageState(
              isActive: _currentTaskLabel.startsWith('메인 바이너리'),
              isDone:
                  progress >= 0.05 && !_currentTaskLabel.startsWith('메인 바이너리'),
            ),
          ),
          _stageTile(
            title: '2. 추가 구성 요소 준비',
            subtitle: '필요한 항목을 이어서 준비합니다',
            state: _resolveTaskDrivenStageState(
              isActive:
                  _currentTaskLabel.startsWith('의존성') ||
                  _currentTaskLabel == '의존성 없음',
              isDone:
                  progress >= 0.90 &&
                  !(_currentTaskLabel.startsWith('의존성') ||
                      _currentTaskLabel == '의존성 없음'),
            ),
          ),
          _stageTile(
            title: '3. 패키지 정보 정리',
            subtitle: '설치에 필요한 정보를 정리합니다',
            state: _resolveTaskDrivenStageState(
              isActive: _currentTaskLabel.contains('매니페스트'),
              isDone: progress >= 0.975 && !_currentTaskLabel.contains('매니페스트'),
            ),
          ),
          _stageTile(
            title: '4. 패키지 파일 생성',
            subtitle: '최종 패키지 파일을 만듭니다',
            state: _resolveTaskDrivenStageState(
              isActive: _currentTaskLabel.contains('.segg'),
              isDone: progress >= 0.995 && !_currentTaskLabel.contains('.segg'),
            ),
          ),
          _stageTile(
            title: '5. 완료',
            subtitle: '저장 위치를 정리하고 마무리합니다',
            state: _resolveStageState(progress, start: 1, end: 1),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPackagingTelemetryPanel() {
    final selectedPackage = _selectedPackage;
    final mainSize = selectedPackage == null ? '-' : _estimatedPayloadLabel();
    final selectedDependencyCount = _selectedDependencies.length;
    final totalDependencyCount = selectedPackage?.dependencies.length ?? 0;
    final transferProgress = _currentProcessedBytes == null
        ? '-'
        : _currentTotalBytes != null && _currentTotalBytes! > 0
        ? '${_formatBytes(_currentProcessedBytes!)} / ${_formatBytes(_currentTotalBytes!)}'
        : _formatBytes(_currentProcessedBytes!);
    final transferSpeed =
        _currentBytesPerSecond == null || _currentBytesPerSecond! <= 0
        ? '-'
        : '${_formatBytes(_currentBytesPerSecond!.round())}/s';
    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelTitle(Icons.podcasts_rounded, '진행 정보'),
          const SizedBox(height: 12),
          _summaryRow('현재 작업', _presentTaskLabel(_currentTaskLabel)),
          _summaryRow('진행률', '${(_packagingProgress * 100).round()}%'),
          _summaryRow('기록 수', '${_logLines.length}'),
          _summaryRow(
            '선택 항목',
            '$selectedDependencyCount / $totalDependencyCount selected',
          ),
          _summaryRow('준비 용량', transferProgress),
          _summaryRow('진행 속도', transferSpeed),
          _summaryRow('예상 크기', mainSize),
          _summaryRow('저장 위치', _displayPath(_settings?.exportRootPath)),
        ],
      ),
    );
  }

  Widget _buildCompletionStep() {
    final result = _packagingResult;
    if (result == null) {
      return Center(
        child: Text(
          '완료된 패키지가 없습니다.',
          style: AppFonts.sourceSans3(color: Colors.white, fontSize: 18),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPanel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.task_alt_rounded,
                        color: Color(0xFF22C55E),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Packaging Completed Successfully',
                            style: AppFonts.lexend(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '실제 파일이 생성되었습니다. 패키지 경로를 복사하거나 폴더를 열 수 있습니다.',
                            style: AppFonts.sourceSans3(
                              color: const Color(0xFF94A3B8),
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _openExportFolder,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Open Folder'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 1024;
                  final leftColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPanelTitle(
                              Icons.info_outline_rounded,
                              'Generated File Information',
                            ),
                            const SizedBox(height: 12),
                            _infoTile(
                              title: 'File Name',
                              value: result.packageFileName,
                            ),
                            const SizedBox(height: 10),
                            _infoTile(
                              title: 'Package Path',
                              value: result.packageFilePath,
                              action: TextButton.icon(
                                onPressed: _copyExportPath,
                                icon: const Icon(
                                  Icons.content_copy_rounded,
                                  size: 16,
                                ),
                                label: const Text('Copy'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPanelTitle(
                              Icons.analytics_outlined,
                              'Package Summary',
                            ),
                            const SizedBox(height: 12),
                            _summaryRow(
                              'Partner',
                              '${result.company.companyName} (${result.company.companyCode})',
                            ),
                            _summaryRow(
                              'Software',
                              '${result.selectedPackage.name} ${result.selectedPackage.version}',
                            ),
                            _summaryRow('OS', result.selectedPackage.os),
                            _summaryRow(
                              'Release Channel',
                              result.selectedPackage.releaseChannel,
                            ),
                            _summaryRow(
                              'Dependency Count',
                              '${result.dependencyArtifacts.length}',
                            ),
                            _summaryRow(
                              'Package Size',
                              _formatBytes(result.packageSizeBytes),
                            ),
                            _summaryRow(
                              'Generated At',
                              _formatDateTime(result.generatedAt),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final rightColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPanelTitle(
                              Icons.verified_user_outlined,
                              'Checksum Verified',
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '메인 바이너리와 선택된 의존성의 xxHash64 검증을 모두 통과했습니다.',
                              style: AppFonts.sourceSans3(
                                color: const Color(0xFF93C5FD),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _summaryRow(
                              'Main Artifact',
                              result.mainArtifact.fileName,
                            ),
                            _summaryRow(
                              'Main Checksum',
                              result.mainArtifact.checksum,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPanelTitle(
                              Icons.layers_clear_rounded,
                              'Included Dependencies',
                            ),
                            const SizedBox(height: 10),
                            if (result.dependencyArtifacts.isEmpty)
                              Text(
                                '포함된 의존성이 없습니다.',
                                style: AppFonts.sourceSans3(
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            for (final dependency in result.dependencyArtifacts)
                              _summaryRow(
                                dependency.fileName,
                                _formatBytes(dependency.sizeBytes),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [],
                        ),
                      ),
                    ],
                  );

                  if (!isWide) {
                    return Column(
                      children: [
                        leftColumn,
                        const SizedBox(height: 16),
                        rightColumn,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: leftColumn),
                      const SizedBox(width: 18),
                      Expanded(flex: 2, child: rightColumn),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1F2937))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          if (_currentStep == 1)
            OutlinedButton.icon(
              onPressed: _isCatalogLoading || _isPackagingRunning
                  ? null
                  : _goToPreviousStep,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Previous Step'),
            ),
          if (_currentStep == 3)
            OutlinedButton.icon(
              onPressed: _isPackagingRunning ? null : _resetWizard,
              icon: const Icon(Icons.first_page_rounded),
              label: const Text('Back to Step 1'),
            ),
          const Spacer(),
          if (_currentStep == 0)
            FilledButton.icon(
              onPressed:
                  _isPartnerCodeComplete &&
                      !_isCatalogLoading &&
                      !_isSettingsLoading
                  ? _authorizePartnerCode
                  : null,
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(
                _isCatalogLoading ? 'Authorizing...' : 'Authorize Access',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          if (_currentStep == 1)
            FilledButton.icon(
              onPressed: !_isPackagingRunning && _canStartPackaging
                  ? _startPackaging
                  : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Start Packaging'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          if (_currentStep == 2)
            FilledButton.icon(
              onPressed: _isPackagingRunning && !_isStopRequested
                  ? _stopPackaging
                  : null,
              icon: const Icon(Icons.stop_rounded),
              label: Text(_isStopRequested ? 'Stopping...' : 'Stop Packaging'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          if (_currentStep == 3)
            FilledButton.icon(
              onPressed: _isPackagingRunning
                  ? null
                  : _startNewPackageFromCurrentAccess,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Start New Package'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: child,
    );
  }

  Widget _buildPanelTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF60A5FA), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppFonts.lexend(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: AppFonts.sourceSans3(
        color: const Color(0xFF8CA3BF),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: AppFonts.sourceSans3(
        color: const Color(0xFFBAE6FD),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: const Color(0xFF08111D),
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 16, 1),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF4B5D75), width: 1.15),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF7DD3FC), width: 1.7),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildGroupDropdownLabel(SoftwareGroupViewModel group) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: group.name,
                style: AppFonts.sourceSans3(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              TextSpan(
                text: '  ${group.codeName}',
                style: AppFonts.sourceSans3(
                  color: const Color(0xFF7DD3FC),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildVersionDropdownLabel(RemoteSoftwarePackage version) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          version.version,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.jetBrainsMono(
            color: const Color(0xFFE0F2FE),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _summaryLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppFonts.sourceSans3(color: const Color(0xFF94A3B8)),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppFonts.sourceSans3(
                color: const Color(0xFFE2E8F0),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required bool done,
    required bool inProgress,
  }) {
    final icon = done
        ? Icons.task_alt_rounded
        : inProgress
        ? Icons.sync_rounded
        : Icons.radio_button_unchecked_rounded;
    final color = done
        ? const Color(0xFF22C55E)
        : inProgress
        ? const Color(0xFF60A5FA)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppFonts.sourceSans3(
              color: const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required String title,
    required String value,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppFonts.sourceSans3(
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: AppFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String metric, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric,
              style: AppFonts.sourceSans3(
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppFonts.sourceSans3(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warningCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF7C2D12).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        message,
        style: AppFonts.sourceSans3(
          color: const Color(0xFFFED7AA),
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _badge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: AppFonts.sourceSans3(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _stageTile({
    required String title,
    required String subtitle,
    required _PackagingStageState state,
    bool isLast = false,
  }) {
    final color = switch (state) {
      _PackagingStageState.done => const Color(0xFF22C55E),
      _PackagingStageState.active => const Color(0xFF60A5FA),
      _PackagingStageState.failed => const Color(0xFFEF4444),
      _PackagingStageState.pending => const Color(0xFF64748B),
    };
    final icon = switch (state) {
      _PackagingStageState.done => Icons.task_alt_rounded,
      _PackagingStageState.active => Icons.play_circle_outline_rounded,
      _PackagingStageState.failed => Icons.error_outline_rounded,
      _PackagingStageState.pending => Icons.radio_button_unchecked_rounded,
    };
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.sourceSans3(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppFonts.sourceSans3(
                    color: const Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            switch (state) {
              _PackagingStageState.done => 'DONE',
              _PackagingStageState.active => 'ACTIVE',
              _PackagingStageState.failed => 'FAILED',
              _PackagingStageState.pending => 'PENDING',
            },
            style: AppFonts.jetBrainsMono(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  _PackagingStageState _resolveStageState(
    double progress, {
    required double start,
    required double end,
  }) {
    if (_packagingError != null && progress >= start) {
      return _PackagingStageState.failed;
    }
    if (progress >= end) {
      return _PackagingStageState.done;
    }
    if (progress >= start) {
      return _PackagingStageState.active;
    }
    return _PackagingStageState.pending;
  }

  _PackagingStageState _resolveTaskDrivenStageState({
    required bool isActive,
    required bool isDone,
  }) {
    if (_packagingError != null && isActive) {
      return _PackagingStageState.failed;
    }
    if (isDone) {
      return _PackagingStageState.done;
    }
    if (isActive) {
      return _PackagingStageState.active;
    }
    return _PackagingStageState.pending;
  }

  Widget _buildNotificationOverlay() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: _headerHeight + 10, right: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final notice in _toastNotices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset: notice.visible
                          ? Offset.zero
                          : const Offset(0.12, -0.04),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: notice.visible ? 1 : 0,
                        child: _buildNotificationCard(notice),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(_ToastNotice notice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: notice.accent.withValues(alpha: 0.45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: notice.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(notice.icon, size: 16, color: notice.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: AppFonts.sourceSans3(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notice.message,
                  style: AppFonts.sourceSans3(
                    color: const Color(0xFFCBD5E1),
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  String _formatBytes(int value) {
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(2)} KB';
    }
    return '$value B';
  }

  String _remoteSizeLabel(RemoteSoftwareBinary binary) {
    if (!binary.hasUri) {
      return '미등록';
    }
    final uri = binary.uri.trim();
    if (_remoteSizeLoadingKeys.contains(uri)) {
      return '조회 중';
    }
    final size = _remoteSizeCache[uri];
    if (size == null) {
      return _remoteSizeCache.containsKey(uri) ? '미확인' : '대기 중';
    }
    return _formatBytes(size);
  }

  String _estimatedPayloadLabel() {
    final selectedPackage = _selectedPackage;
    if (selectedPackage == null) {
      return '-';
    }

    final expectedBinaries = <RemoteSoftwareBinary>[
      selectedPackage.mainBinary,
      ..._selectedDependencies,
    ];
    if (expectedBinaries.isEmpty) {
      return '0 B';
    }

    var totalBytes = 0;
    var hasMissingUri = false;
    var hasLoading = false;
    var hasUnknown = false;

    for (final binary in expectedBinaries) {
      if (!binary.hasUri) {
        hasMissingUri = true;
        continue;
      }

      final uri = binary.uri.trim();
      if (_remoteSizeLoadingKeys.contains(uri) ||
          !_remoteSizeCache.containsKey(uri)) {
        hasLoading = true;
        continue;
      }

      final size = _remoteSizeCache[uri];
      if (size == null) {
        hasUnknown = true;
        continue;
      }
      totalBytes += size;
    }

    final totalLabel = _formatBytes(totalBytes);
    if (hasLoading) {
      return totalBytes > 0 ? '$totalLabel + 조회 중' : '조회 중';
    }
    if (hasMissingUri) {
      return totalBytes > 0 ? '$totalLabel + 미등록' : '미등록 포함';
    }
    if (hasUnknown) {
      return totalBytes > 0 ? '$totalLabel + 미확인' : '미확인';
    }
    return totalLabel;
  }

  String _packageAvailabilityLabel(RemoteSoftwarePackage softwarePackage) {
    final mainMissing = !softwarePackage.mainBinary.hasUri;
    final dependencyMissing = softwarePackage.hasMissingDependencyUri;
    if (!mainMissing && !dependencyMissing) {
      return '패키징 가능';
    }
    if (mainMissing && dependencyMissing) {
      return '메인/의존성 누락';
    }
    if (mainMissing) {
      return '메인 파일 미등록';
    }
    return '의존성 경로 누락';
  }

  Color _packageAvailabilityColor(RemoteSoftwarePackage softwarePackage) {
    return softwarePackage.canPackage
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
  }

  Color _logColor(String level) {
    switch (level) {
      case 'DONE':
        return const Color(0xFF22C55E);
      case 'ERROR':
        return const Color(0xFFEF4444);
      case 'WARN':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF60A5FA);
    }
  }
}

class _StepMeta {
  const _StepMeta({
    required this.index,
    required this.label,
    required this.detail,
  });

  final int index;
  final String label;
  final String detail;
}

class _LogLine {
  _LogLine({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final String level;
  final String message;

  String get timeText {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String get asPlainText => '[$timeText] $level $message';
}

class _ToastNotice {
  _ToastNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  bool visible = true;
}

enum _PackagingStageState { pending, active, done, failed }
