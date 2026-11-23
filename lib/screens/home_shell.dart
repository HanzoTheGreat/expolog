import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'catalog_tab.dart';
import 'exposure_tab.dart';
import 'live_exposure_screen.dart';
import 'timeline_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        // Crash-/Neustart-Recovery: Eine laufende Exposition hat immer Vorrang
        final activeSession = widget.state.activeExposureSession;
        if (activeSession != null) {
          return LiveExposureScreen(
            state: widget.state,
            session: activeSession,
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              ExposureTab(state: widget.state),
              TimelineTab(state: widget.state),
              CatalogTab(state: widget.state),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) =>
                setState(() => _selectedIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.timer_outlined),
                selectedIcon: Icon(Icons.timer),
                label: 'Exposition',
              ),
              NavigationDestination(
                icon: Icon(Icons.view_timeline_outlined),
                selectedIcon: Icon(Icons.view_timeline),
                label: 'Zeitstrahl',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'Katalog',
              ),
            ],
          ),
        );
      },
    );
  }
}
