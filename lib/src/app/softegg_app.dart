import 'package:flutter/material.dart';

import '../services/install_runtime_service.dart';
import '../services/softegg_snapshot_service.dart';
import '../state/softegg_controller.dart';
import '../ui/softegg_page.dart';

class SoftEggApp extends StatefulWidget {
  const SoftEggApp({super.key});

  @override
  State<SoftEggApp> createState() => _SoftEggAppState();
}

class _SoftEggAppState extends State<SoftEggApp> {
  late final Future<SoftEggController> _controllerFuture;

  @override
  void initState() {
    super.initState();
    _controllerFuture = _createController();
  }

  Future<SoftEggController> _createController() async {
    final runtime = InstallRuntimeService();
    final snapshotService = SoftEggSnapshotService();
    final controller = SoftEggController(
      snapshotService: snapshotService,
      runtime: runtime,
    );
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoftEgg',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0DCCF2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: FutureBuilder<SoftEggController>(
        future: _controllerFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return SoftEggPage(controller: snapshot.data!);
        },
      ),
    );
  }
}
