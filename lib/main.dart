import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/unlock_screen.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ExpoLogApp());
}

class ExpoLogApp extends StatefulWidget {
  const ExpoLogApp({super.key});

  @override
  State<ExpoLogApp> createState() => _ExpoLogAppState();
}

class _ExpoLogAppState extends State<ExpoLogApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState()..init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExpoLog',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          if (_state.initializing) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_state.isUnlocked) {
            return UnlockScreen(state: _state);
          }
          return HomeShell(state: _state);
        },
      ),
    );
  }
}
