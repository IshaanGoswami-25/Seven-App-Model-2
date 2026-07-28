import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';

/// The global AuthGateway that manages authentication state,
/// queries the user profile, and directs users to either
/// AuthScreen, the Onboarding flow, or the Dashboard.
class AuthGateway extends StatefulWidget {
  const AuthGateway({super.key});

  @override
  State<AuthGateway> createState() => _AuthGatewayState();
}

class _AuthGatewayState extends State<AuthGateway> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _isLoading = true;
  Session? _session;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _initAuthListener();
  }

  void _initAuthListener() {
    _session = Supabase.instance.client.auth.currentSession;
    if (_session != null) {
      _checkOnboardingStatus(_session!.user.id);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final Session? session = data.session;
      if (!mounted) return;

      setState(() {
        _session = session;
      });

      if (session != null) {
        await _checkOnboardingStatus(session.user.id);
      } else {
        setState(() {
          _onboardingComplete = false;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _checkOnboardingStatus(String userId) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Query the profiles table for the onboarding status of the current user
      final data = await Supabase.instance.client
          .from('profiles')
          .select('onboarding_complete')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null && data['onboarding_complete'] == true) {
            _onboardingComplete = true;
          } else {
            _onboardingComplete = false;
          }
        });
      }
    } catch (e) {
      // If the profile does not exist yet (e.g. fresh signup) or there is an issue,
      // fallback to showing the onboarding flow (onboarding_complete = false)
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 2: Loading State during authenticated cache check
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF050507),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6366F1),
          ),
        ),
      );
    }

    // Phase 1: Unauthenticated State
    if (_session == null) {
      return const AuthScreen();
    }

    // Phase 3: Authenticated Redirect (Onboarding vs Main Dashboard)
    return DashboardScreen(
      initialOnboardingComplete: _onboardingComplete,
      onOnboardingCompleted: () {
        setState(() {
          _onboardingComplete = true;
        });
      },
    );
  }
}
