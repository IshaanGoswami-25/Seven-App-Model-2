import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_screen.dart';
import 'music_visualizer.dart';
import 'profile_theme.dart';
import 'interactive_3d_card.dart';

class PublicProfileViewScreen extends StatefulWidget {
  final String username;

  const PublicProfileViewScreen({
    super.key,
    required this.username,
  });

  @override
  State<PublicProfileViewScreen> createState() => _PublicProfileViewScreenState();
}

class _PublicProfileViewScreenState extends State<PublicProfileViewScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;

  // Profile Data
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _socialLinksData;
  Map<String, dynamic>? _connectionData;

  // Session user info
  String? _currentUserId;
  StreamSubscription<AuthState>? _authSubscription;

  // Spotify Vinyl Disk Animation Controller
  late AnimationController _vinylController;

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
    _loadPublicProfile();

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final newUserId = data.session?.user.id;
      if (newUserId != _currentUserId) {
        _loadPublicProfile();
      }
    });
  }

  @override
  void dispose() {
    _vinylController.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPublicProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      _currentUserId = client.auth.currentUser?.id;

      // 1. Fetch public profile row based on unique username
      final profile = await client
          .from('profiles')
          .select()
          .eq('username', widget.username.trim().toLowerCase())
          .maybeSingle();

      if (profile == null) {
        setState(() {
          _error = 'User "@${widget.username}" does not exist.';
          _isLoading = false;
        });
        return;
      }

      _profileData = profile;
      final targetUserId = profile['id'] as String;

      // 2. Fetch social link vectors and connection matrix in parallel
      final futures = await Future.wait<dynamic>([
        client.from('social_links').select().eq('id', targetUserId).maybeSingle(),
        if (_currentUserId != null && _currentUserId != targetUserId)
          client
              .from('connections')
              .select()
              .or('and(sender_id.eq.$_currentUserId,receiver_id.eq.$targetUserId),and(sender_id.eq.$targetUserId,receiver_id.eq.$_currentUserId)')
              .maybeSingle()
        else
          Future.value(null),
      ]);

      _socialLinksData = futures[0];
      _connectionData = futures[1];

      _vinylController.repeat();
    } catch (e) {
      _error = 'An error occurred loading profile metadata: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Active Social Media Link Interception Launcher
  Future<void> _launchSocialLink(String platform, String username) async {
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('@${widget.username} has not linked their $platform.'),
          backgroundColor: const Color(0xFF1C1C24),
        ),
      );
      return;
    }

    String nativeUrlString = '';
    String webUrlString = '';

    switch (platform.toLowerCase()) {
      case 'instagram':
        nativeUrlString = 'instagram://user?username=$username';
        webUrlString = 'https://instagram.com/$username';
        break;
      case 'linkedin':
        nativeUrlString = 'linkedin://in/$username';
        webUrlString = 'https://linkedin.com/in/$username';
        break;
      case 'github':
        nativeUrlString = 'github://user/$username';
        webUrlString = 'https://github.com/$username';
        break;
      case 'spotify':
        nativeUrlString = 'spotify:user:$username';
        webUrlString = 'https://open.spotify.com/user/$username';
        break;
    }

    final Uri nativeUri = Uri.parse(nativeUrlString);
    final Uri webUri = Uri.parse(webUrlString);

    try {
      if (nativeUrlString.isNotEmpty && await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalNonBrowserApplication);
      } else {
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch URL';
        }
      }
    } catch (e) {
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to open $platform link for $username'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  // Connection State Machine Action handlers
  Future<void> _sendConnectRequest() async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to send connection requests.'),
          backgroundColor: Color(0xFF6366F1),
        ),
      );
      return;
    }

    final targetUserId = _profileData!['id'] as String;

    try {
      final client = Supabase.instance.client;
      await client.from('connections').insert({
        'sender_id': _currentUserId,
        'receiver_id': targetUserId,
        'status': 'pending',
      });
      _loadPublicProfile(); // Refresh connection status
    } catch (e) {
      _showSnackbarError('Failed to send invite: ${e.toString()}');
    }
  }

  Future<void> _acceptConnection(String connectionId) async {
    try {
      final client = Supabase.instance.client;
      await client.from('connections').update({
        'status': 'accepted',
      }).eq('id', connectionId);
      _loadPublicProfile();
    } catch (e) {
      _showSnackbarError('Failed to accept: ${e.toString()}');
    }
  }

  Future<void> _declineConnection(String connectionId) async {
    try {
      final client = Supabase.instance.client;
      await client.from('connections').delete().eq('id', connectionId);
      _loadPublicProfile();
    } catch (e) {
      _showSnackbarError('Failed to decline request: ${e.toString()}');
    }
  }

  Future<void> _removeConnection(String connectionId) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final client = Supabase.instance.client;
      await client.from('connections').delete().eq('id', connectionId);
      await _loadPublicProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend removed successfully.'),
            backgroundColor: Color(0xFF1C1C24),
          ),
        );
      }
    } catch (e) {
      _showSnackbarError('Failed to remove friend: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showRemoveFriendDialog(String connectionId) async {
    final displayName = _profileData?['display_name'] ?? 'this user';
    final username = widget.username;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
          ),
          title: Text(
            'Remove Friend',
            style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
          ),
          content: Text(
            'Are you sure you want to remove $displayName (@$username) from your connections?',
            style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _removeConnection(connectionId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                'Remove',
                style: GoogleFonts.firaSans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSnackbarError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF05A30),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E), fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeTheme = ProfileThemeColors.getTheme(_profileData?['card_theme']);
    final displayName = _profileData?['display_name'] ?? 'Anonymous';
    final avatarUrlString = _profileData?['avatar_url'];
    final birthday = _profileData?['birthday'] ?? 'Not set';
    final phoneNumber = _profileData?['phone_number'] ?? 'Not set';

    final instagram = _socialLinksData?['instagram'] ?? '';
    final linkedin = _socialLinksData?['linkedin'] ?? '';
    final github = _socialLinksData?['github'] ?? '';
    final spotify = _socialLinksData?['spotify'] ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '@${widget.username}',
          style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Bento Matrix Content
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 12.0, bottom: 120.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Interactive3DCard(
                  name: displayName,
                  username: widget.username,
                  phoneNumber: phoneNumber,
                ),
                SizedBox(height: 16),
                // Header profile card
                Container(
                  padding: EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color ?? Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFFFDF0ED),
                            backgroundImage: avatarUrlString != null ? NetworkImage(avatarUrlString) : null,
                            child: avatarUrlString == null
                                ? Icon(Icons.person, size: 40, color: Color(0xFFF05A30))
                                : null,
                          ),
                          SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: GoogleFonts.firaSans(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.cake_outlined, size: 14, color: Color(0xFFF05A30)),
                                    SizedBox(width: 6),
                                    Text(
                                      birthday,
                                      style: GoogleFonts.firaSans(fontSize: 13, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.phone_outlined, size: 14, color: Color(0xFFF05A30)),
                                    SizedBox(width: 6),
                                    Text(
                                      phoneNumber,
                                      style: GoogleFonts.firaSans(fontSize: 13, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_profileData?['course'] != null && (_profileData?['course'] as String).isNotEmpty) ...[
                        SizedBox(height: 16),
                        _buildPublicBranchDetailsBanner(activeTheme),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 16),

                // Grid (Instagram & LinkedIn)
                Row(
                  children: [
                    Expanded(
                      child: _BentoHoverWrapper(
                        onTap: () => _launchSocialLink('instagram', instagram),
                        child: Container(
                          height: 180,
                          padding: EdgeInsets.all(20.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color ?? Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFE1306C).withValues(alpha: 0.04),
                                Colors.transparent,
                              ],
                              radius: 1.2,
                              center: Alignment.topRight,
                              ),
                            ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE1306C).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      color: Color(0xFFE1306C),
                                      size: 22,
                                    ),
                                  ),
                                  Icon(Icons.north_east_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 18),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Instagram',
                                    style: GoogleFonts.firaSans(
                                      fontSize: 15,
                                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    instagram.isNotEmpty ? '@$instagram' : 'Unlinked',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.firaSans(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: instagram.isNotEmpty ? Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E) : Colors.black38,
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _BentoHoverWrapper(
                        onTap: () => _launchSocialLink('linkedin', linkedin),
                        child: Container(
                          height: 180,
                          padding: EdgeInsets.all(20.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color ?? Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFF0077B5).withValues(alpha: 0.04),
                                Colors.transparent,
                              ],
                              radius: 1.2,
                              center: Alignment.topRight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0077B5).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.work_rounded,
                                      color: Color(0xFF0077B5),
                                      size: 22,
                                    ),
                                  ),
                                  Icon(Icons.north_east_rounded, color: Colors.white30, size: 18),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LinkedIn',
                                    style: GoogleFonts.firaSans(
                                      fontSize: 15,
                                      color: Colors.white54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    linkedin.isNotEmpty ? linkedin : 'Unlinked',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.firaSans(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: linkedin.isNotEmpty ? Colors.white : Colors.white30,
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),

                // GitHub Wide Card
                _BentoHoverWrapper(
                  onTap: () => _launchSocialLink('github', github),
                  child: Container(
                    padding: EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ?? Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                          ),
                          child: Icon(
                            Icons.code_rounded,
                            color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                            size: 28,
                          ),
                        ),
                        SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GitHub Vector',
                                style: GoogleFonts.firaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                github.isNotEmpty ? 'github.com/$github' : 'Unlinked',
                                style: GoogleFonts.firaSans(
                                  fontSize: 14,
                                  color: github.isNotEmpty ? Colors.black54 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.north_east_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 18),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Spotify Wide Card with Rotation
                _BentoHoverWrapper(
                  onTap: () => _launchSocialLink('spotify', spotify),
                  child: Container(
                    padding: EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ?? Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        RotationTransition(
                          turns: _vinylController,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF09090C),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF1DB954), width: 1.5),
                              image: const DecorationImage(
                                image: NetworkImage('https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=150&auto=format&fit=crop&q=60'),
                                fit: BoxFit.cover,
                                opacity: 0.7,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardTheme.color ?? Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Spotify Soundtrack',
                                style: GoogleFonts.firaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                spotify.isNotEmpty ? 'spotify.com/$spotify' : 'Unlinked',
                                style: GoogleFonts.firaSans(
                                  fontSize: 14,
                                  color: spotify.isNotEmpty ? Colors.black54 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (spotify.isNotEmpty) ...[
                          MusicVisualizer(
                            barColor: const Color(0xFF1DB954),
                            isPlaying: true,
                          ),
                          SizedBox(width: 12),
                        ],
                        Icon(Icons.north_east_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating Action Bottom Panel
          if (_currentUserId != _profileData!['id'])
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildActionPanel(),
            ),
        ],
      ),
    );
  }

  // CONNECTION BASE ACTION PANEL STATE MACHINE RENDERING
  Widget _buildActionPanel() {
    final activeTheme = ProfileThemeColors.getTheme(_profileData?['card_theme']);

    // If not logged in, prompt user to login
    if (_currentUserId == null) {
      return Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Log in to connect with @${widget.username}',
                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87), fontSize: 14),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                // Push AuthScreen as a modal route
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: activeTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 0,
              ),
              child: Text(
                'Login',
                style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    // Evaluate Connection Relationship State Vector
    if (_connectionData == null) {
      // State Vector A: No connection exists -> Render prominent "BECOME FRIENDS"
      final isWeb = kIsWeb;
      return _buildActionButton(
        label: isWeb ? 'ADD TO FRIENDS (OPEN APP)' : 'BECOME FRIENDS',
        icon: Icons.person_add_outlined,
        onPressed: isWeb
            ? () async {
                HapticFeedback.mediumImpact();
                final String customUriString = 'seven://p/${widget.username}';
                final Uri customUri = Uri.parse(customUriString);
                try {
                  if (await canLaunchUrl(customUri)) {
                    await launchUrl(customUri, mode: LaunchMode.externalNonBrowserApplication);
                  } else {
                    await launchUrl(customUri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Opening Hexa app for @${widget.username}...'),
                        backgroundColor: activeTheme.primary,
                      ),
                    );
                  }
                }
              }
            : () {
                HapticFeedback.mediumImpact();
                _sendConnectRequest();
              },
        color: activeTheme.primary,
      );
    }

    final status = _connectionData!['status'] as String;
    final senderId = _connectionData!['sender_id'] as String;
    final connectionId = _connectionData!['id'] as String;

    if (status == 'pending') {
      if (senderId == _currentUserId) {
        // State Vector B: Pending - Current User is the Sender -> Disabled "REQUEST PENDING"
        return _buildActionButton(
          label: 'REQUEST PENDING',
          icon: Icons.hourglass_empty_rounded,
          onPressed: null,
          color: Colors.grey.withValues(alpha: 0.3),
        );
      } else {
        // State Vector C: Pending - Current User is the Receiver -> Split "ACCEPT" & "DECLINE"
        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '@${widget.username} sent you a connection invite.',
                textAlign: TextAlign.center,
                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87), fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _declineConnection(connectionId);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.redAccent, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'DECLINE',
                        style: GoogleFonts.firaSans(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _acceptConnection(connectionId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        'ACCEPT',
                        style: GoogleFonts.firaSans(color: Theme.of(context).cardTheme.color ?? Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }
    } else if (status == 'accepted') {
      // State Vector D: Connection is Accepted -> Labeled "FRIENDS" with checkmark icon. Clicking it allows removing friend.
      return _buildActionButton(
        label: 'FRIENDS',
        icon: Icons.check_circle_outline_rounded,
        onPressed: () {
          HapticFeedback.mediumImpact();
          _showRemoveFriendDialog(connectionId);
        },
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderColor: activeTheme.primary,
        textColor: activeTheme.primary,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    Color? borderColor,
    Color? textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: textColor ?? Colors.white, size: 20),
        label: Text(
          label,
          style: GoogleFonts.firaSans(
            fontWeight: FontWeight.bold,
            color: textColor ?? Colors.white,
            fontSize: 15,
            letterSpacing: 1.0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: borderColor != null ? BorderSide(color: borderColor, width: 1.5) : BorderSide.none,
          ),
          padding: EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildPublicBranchDetailsBanner(ProfileThemeColors activeTheme) {
    final String course = _profileData?['course'] ?? '';
    final String? branch = _profileData?['branch'];
    final String? section = _profileData?['section'];

    String bannerText = course;
    if (course == 'Btech' && branch != null && branch.isNotEmpty) {
      bannerText = 'B.Tech ($branch)';
    }
    if (section != null && section.isNotEmpty) {
      bannerText += ' | Section $section';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: activeTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: activeTheme.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.school_rounded,
            color: activeTheme.primary,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              bannerText,
              style: GoogleFonts.firaSans(
                color: activeTheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Private Hover touch Scale Transition wrapper
class _BentoHoverWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _BentoHoverWrapper({
    required this.child,
    required this.onTap,
  });

  @override
  State<_BentoHoverWrapper> createState() => _BentoHoverWrapperState();
}

class _BentoHoverWrapperState extends State<_BentoHoverWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
