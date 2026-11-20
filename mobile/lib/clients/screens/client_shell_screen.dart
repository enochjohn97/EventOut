import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/client_auth_provider.dart';
import '../providers/client_data_provider.dart';
import '../widgets/client_detail_sheets.dart';
import '../widgets/create_event_sheet.dart';
import 'client_events_screen.dart';
import 'client_home_screen.dart';
import 'client_payments_screen.dart';
import 'client_profile_screen.dart';
import 'client_tickets_screen.dart';

/// Organizer home shell: Home · Events · Tickets · Payments · Profile. The
/// create-event button lives on the Events tab only.
class ClientShellScreen extends StatefulWidget {
  const ClientShellScreen({super.key});

  @override
  State<ClientShellScreen> createState() => _ClientShellScreenState();
}

class _ClientShellScreenState extends State<ClientShellScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  Timer? _poll;

  /// Same cadence as the web client dashboard: every 30 seconds while the app
  /// is in the foreground, so new sales, payments and web edits appear on the
  /// phone without the organizer pulling to refresh.
  static const _refreshInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(force: true));
    _poll = Timer.periodic(_refreshInterval, (_) => _load(force: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    final auth = context.read<ClientAuthProvider>();
    var id = auth.client?.profileId;
    if (id == null) {
      // Cold start / restored session: make sure the organizer profile has
      // been resolved before the first data request goes out.
      if (auth.status == ClientAuthStatus.unknown) {
        await auth.bootstrap();
      } else if (auth.status == ClientAuthStatus.authenticated) {
        await auth.refreshProfile();
      }
      if (!mounted) return;
      id = auth.client?.profileId;
    }
    if (id == null) return;
    await context.read<ClientDataProvider>().load(id, force: force);
  }

  Future<void> _createEvent() async {
    final created = await showCreateEventSheet(context);
    if (!mounted || !created) return;
    final newEventId = takeLastCreatedEventId();
    await _load(force: true);
    if (!mounted) return;
    setState(() => _index = 1);
    if (newEventId != null) {
      // Open the new event's preview so the organizer can pay for it and
      // publish it straight away.
      final data = context.read<ClientDataProvider>();
      for (final event in data.events) {
        if (event.id != newEventId) continue;
        await showClientEventDetails(
          context,
          event,
          onChanged: () async {
            final id = context.read<ClientAuthProvider>().client?.profileId;
            if (id != null) await data.refresh(id);
          },
        );
        break;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Event created. It will appear on the app and website.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _selectTab(int index) {
    setState(() => _index = index);
    if (index == 0 || index == 1 || index == 2 || index == 3) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ClientHomeScreen(onSelectTab: _selectTab, onCreateEvent: _createEvent),
      ClientEventsScreen(onCreateEvent: _createEvent),
      const ClientTicketsScreen(),
      const ClientPaymentsScreen(),
      const ClientProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bgPage,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Tickets',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Payments',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
