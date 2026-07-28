import 'main.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'google_fonts_alias.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'friends_tab.dart';
import 'branch_details_edit_screen.dart';
import 'profile_theme.dart';
import 'community_tab.dart';
import 'schedule_tab.dart';
import 'plus_card_screen.dart';
import 'developed_by_footer.dart';

class DashboardScreen extends StatefulWidget {
  final bool initialOnboardingComplete;
  final VoidCallback onOnboardingCompleted;

  const DashboardScreen({
    super.key,
    required this.initialOnboardingComplete,
    required this.onOnboardingCompleted,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  // Navigation & Onboarding States
  late bool _onboardingComplete;
  int _onboardingStep = 1;
  bool _isSaving = false;
  int _currentTab = 0;
  bool _isConfirmingSelfie = false;

  // Onboarding Step 1: Social Links Controllers
  final _socialFormKey = GlobalKey<FormState>();
  final _instagramController = TextEditingController();
  final _linkedinController = TextEditingController();
  final _githubController = TextEditingController();
  final _spotifyController = TextEditingController();

  // Onboarding Step 2: Identity Controllers
  final _identityFormKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _birthdayController = TextEditingController();

  // Avatar Upload States
  Uint8List? _avatarBytes;
  String? _avatarName;
  String? _avatarUrl;
  bool _isUploadingAvatar = false;

  // Dashboard Data State
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _socialLinksData;
  List<Map<String, dynamic>> _scheduleItems = [];
  bool _isLoadingDashboard = false;

  // Vinyl Rotation Animation Controller for Spotify Card
  late AnimationController _vinylController;

  // Realtime Notification subscriptions
  RealtimeChannel? _connectionsChannel;
  RealtimeChannel? _messagesChannel;
  bool _hasNewInviteNotification = false;
  bool _hasNewMessageNotification = false;

  @override
  void initState() {
    super.initState();
    _onboardingComplete = widget.initialOnboardingComplete;

    _vinylController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );

    if (_onboardingComplete) {
      _loadDashboardData();
      _vinylController.repeat();
      _setupRealtimeNotifications();
    }
  }

  @override
  void dispose() {
    _cleanupRealtimeNotifications();
    _instagramController.dispose();
    _linkedinController.dispose();
    _githubController.dispose();
    _spotifyController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _phoneNumberController.dispose();
    _birthdayController.dispose();
    _vinylController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingDashboard = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final responses = await Future.wait([
        Supabase.instance.client.from('profiles').select().eq('id', userId).maybeSingle(),
        Supabase.instance.client.from('social_links').select().eq('id', userId).maybeSingle(),
        Supabase.instance.client.from('class_schedule').select().eq('user_id', userId).order('lecture_index', ascending: true),
      ]);

      if (mounted) {
        setState(() {
          _profileData = responses[0] as Map<String, dynamic>?;
          _socialLinksData = responses[1] as Map<String, dynamic>?;
          // Pre-populate controllers for potential dashboard editing or fallback
          if (_profileData != null) {
            _usernameController.text = _profileData!['username'] ?? '';
            _displayNameController.text = _profileData!['display_name'] ?? '';
            _phoneNumberController.text = _profileData!['phone_number'] ?? '';
            _birthdayController.text = _profileData!['birthday'] ?? '';
            _avatarUrl = _profileData!['avatar_url'];
          }
          if (_socialLinksData != null) {
            _instagramController.text = _socialLinksData!['instagram'] ?? '';
            _linkedinController.text = _socialLinksData!['linkedin'] ?? '';
            _githubController.text = _socialLinksData!['github'] ?? '';
            _spotifyController.text = _socialLinksData!['spotify'] ?? '';
          }
          _scheduleItems = List<Map<String, dynamic>>.from(responses[2] as List? ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dashboard: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDashboard = false;
        });
      }
    }
  }

  // Pick Profile Image from Gallery
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _avatarBytes = bytes;
          _avatarName = image.name;
          _isConfirmingSelfie = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting image: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Upload Selected Image to Supabase Storage
  Future<String?> _uploadAvatar(String userId) async {
    if (_avatarBytes == null || _avatarName == null) return _avatarUrl;

    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      final fileExtension = _avatarName!.split('.').last;
      final fileName = '$userId.$fileExtension';
      final storagePath = fileName;

      // Upload binary bytes directly to 'avatars' bucket
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            storagePath,
            _avatarBytes!,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(storagePath);

      return publicUrl;
    } catch (e) {
      throw Exception('Avatar upload failed: ${e.toString()}');
    } finally {
      setState(() {
        _isUploadingAvatar = false;
      });
    }
  }

  // Date of Birth DatePicker helper
  Future<void> _selectBirthday() async {
    DateTime initialDate = DateTime(2000, 1, 1);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFF05A30),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E1E1E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _birthdayController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  // Save profiles & social links concurrently and flip state to Dashboard
  Future<void> _finalizeOnboarding() async {
    if (!_identityFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Upload avatar if selected
      String? finalAvatarUrl = _avatarUrl;
      if (_avatarBytes != null) {
        finalAvatarUrl = await _uploadAvatar(userId);
        setState(() {
          _avatarUrl = finalAvatarUrl;
        });
      }

      // 2. Concurrently insert/update profiles and social_links
      await Future.wait([
        Supabase.instance.client.from('profiles').upsert({
          'id': userId,
          'username': _usernameController.text.trim().toLowerCase(),
          'display_name': _displayNameController.text.trim(),
          'phone_number': _phoneNumberController.text.trim(),
          'birthday': _birthdayController.text.trim(),
          'avatar_url': finalAvatarUrl,
          'onboarding_complete': true,
        }),
        Supabase.instance.client.from('social_links').upsert({
          'id': userId,
          'instagram': _instagramController.text.trim(),
          'linkedin': _linkedinController.text.trim(),
          'github': _githubController.text.trim(),
          'spotify': _spotifyController.text.trim(),
        }),
      ]);

      // 3. Update local states and notify gateway
      setState(() {
        _onboardingComplete = true;
      });

      _vinylController.repeat();
      await _loadDashboardData();
      _setupRealtimeNotifications();
      widget.onOnboardingCompleted();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile onboarding finalized successfully!'),
            backgroundColor: Color(0xFFF05A30),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Color(0xFFE5E5E5), width: 1.0),
            ),
            title: Text(
              'Submission Error',
              style: GoogleFonts.firaSans(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              e.toString(),
              style: GoogleFonts.firaSans(color: Colors.black87),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Dismiss',
                  style: GoogleFonts.firaSans(
                    color: const Color(0xFFF05A30),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // Native Deep Linking Launch Routine
  Future<void> _launchSocialLink(String platform, String username) async {
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No $platform username configured.'),
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
          throw 'Could not launch fallback browser link.';
        }
      }
    } catch (e) {
      // Direct Web URL fallback
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

  Future<void> _signOut() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Color(0xFFE5E5E5), width: 1.0),
          ),
          title: Text(
            'Confirm Logout',
            style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: const Color(0xFF1E1E1E)),
          ),
          content: Text(
            'Are you sure you want to log out of your Hexa account?',
            style: GoogleFonts.firaSans(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.firaSans(color: Colors.black54, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _executeSignOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF05A30),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                'Logout',
                style: GoogleFonts.firaSans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign out error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingComplete) {
      return _buildDashboardView();
    }
    if (_isConfirmingSelfie) {
      return _buildConfirmSelfieView();
    }
    return _buildOnboardingView();
  }

  // ==========================================
  // CONFIRM SELFIE VIEW WIDGET
  // ==========================================
  Widget _buildConfirmSelfieView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EFEF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Container(
              padding: const EdgeInsets.all(32.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE5E5E5), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Confirm Your Selfie',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.firaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your face is clearly visible.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.firaSans(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFF05A30),
                          width: 3.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF05A30).withValues(alpha: 0.15),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                        image: _avatarBytes != null
                            ? DecorationImage(
                                image: MemoryImage(_avatarBytes!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _avatarBytes == null
                          ? const Icon(
                              Icons.person_outline,
                              size: 72,
                              color: Colors.black26,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isConfirmingSelfie = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF05A30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Confirm photo',
                        style: GoogleFonts.firaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _pickImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFDF0ED),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Retake photo',
                        style: GoogleFonts.firaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFF05A30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ONBOARDING VIEW WIDGETS
  // ==========================================
  Widget _buildOnboardingView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EFEF),
      appBar: AppBar(
        title: Text(
          'Onboarding Step $_onboardingStep of 2',
          style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: const Color(0xFF1E1E1E)),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: null,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF1E1E1E)),
            onPressed: _signOut,
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step Progress Line
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF05A30),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: _onboardingStep >= 2
                            ? const Color(0xFFF05A30)
                            : const Color(0xFFE5E5E5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE5E5E5), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: _onboardingStep == 1
                    ? _buildOnboardingStep1()
                    : _buildOnboardingStep2(),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // STEP 1: Social Directory Vectors
  Widget _buildOnboardingStep1() {
    return Form(
      key: _socialFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Social Directory Vectors',
            style: GoogleFonts.firaSans(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E1E1E)),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your digital footprints. Enter your usernames/handles below.',
            style: GoogleFonts.firaSans(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 28),
          // Instagram Input
          TextFormField(
            controller: _instagramController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            decoration: const InputDecoration(
              labelText: 'Instagram Username',
              hintText: 'e.g. janesmith',
              prefixIcon: Icon(Icons.camera_alt_outlined, color: Colors.black45),
            ),
          ),
          const SizedBox(height: 18),
          // LinkedIn Input
          TextFormField(
            controller: _linkedinController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            decoration: const InputDecoration(
              labelText: 'LinkedIn Profile Username',
              hintText: 'e.g. jane-smith-1234',
              prefixIcon: Icon(Icons.work_outline, color: Colors.black45),
            ),
          ),
          const SizedBox(height: 18),
          // GitHub Input
          TextFormField(
            controller: _githubController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            decoration: const InputDecoration(
              labelText: 'GitHub Username',
              hintText: 'e.g. janesmithdev',
              prefixIcon: Icon(Icons.code_outlined, color: Colors.black45),
            ),
          ),
          const SizedBox(height: 18),
          // Spotify Input
          TextFormField(
            controller: _spotifyController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            decoration: const InputDecoration(
              labelText: 'Spotify User ID',
              hintText: 'e.g. spotify_username',
              prefixIcon: Icon(Icons.music_note_outlined, color: Colors.black45),
            ),
          ),
          const SizedBox(height: 32),
          // Action Button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                if (_socialFormKey.currentState!.validate()) {
                  setState(() {
                    _onboardingStep = 2;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF05A30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              child: Text(
                'Next Step',
                style: GoogleFonts.firaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 2: Identity Details & Media
  Widget _buildOnboardingStep2() {
    return Form(
      key: _identityFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Profile & Identity',
            style: GoogleFonts.firaSans(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E1E1E)),
          ),
          const SizedBox(height: 8),
          Text(
            'Set up your identification card and profile avatar.',
            style: GoogleFonts.firaSans(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 28),

          // Avatar Picker Container
          Center(
            child: Stack(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF0ED),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE5E5E5),
                      width: 2.5,
                    ),
                    image: _avatarBytes != null
                        ? DecorationImage(image: MemoryImage(_avatarBytes!), fit: BoxFit.cover)
                        : (_avatarUrl != null
                            ? DecorationImage(image: NetworkImage(_avatarUrl!), fit: BoxFit.cover)
                            : null),
                  ),
                  child: _avatarBytes == null && _avatarUrl == null
                      ? const Icon(
                          Icons.person_outline,
                          size: 48,
                          color: Color(0xFFF05A30),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF05A30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Username Field
          TextFormField(
            controller: _usernameController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            decoration: const InputDecoration(
              labelText: 'Username / NFC Handle',
              hintText: 'e.g. janesmith',
              prefixIcon: Icon(Icons.alternate_email_outlined, color: Colors.black45),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Username is required';
              }
              final regExp = RegExp(r'^[a-z0-9_]{3,15}$');
              if (!regExp.hasMatch(value.trim())) {
                return 'Use 3-15 lowercase letters, numbers, or underscores';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          // Display Name
          TextFormField(
            controller: _displayNameController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            decoration: const InputDecoration(
              labelText: 'Display Name',
              hintText: 'e.g. Jane Smith',
              prefixIcon: Icon(Icons.badge_outlined, color: Colors.black45),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Display name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          // Phone Number
          TextFormField(
            controller: _phoneNumberController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: 'e.g. +1 555-0199',
              prefixIcon: Icon(Icons.phone_outlined, color: Colors.black45),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Phone number is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          // Birthday Picker
          TextFormField(
            controller: _birthdayController,
            style: GoogleFonts.firaSans(color: const Color(0xFF1E1E1E)),
            readOnly: true,
            onTap: _selectBirthday,
            decoration: const InputDecoration(
              labelText: 'Date of Birth',
              hintText: 'YYYY-MM-DD',
              prefixIcon: Icon(Icons.cake_outlined, color: Colors.black45),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Date of birth is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          // Action Buttons (Back + Submit)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() {
                              _onboardingStep = 1;
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFDF0ED),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: Text(
                      'Back',
                      style: GoogleFonts.firaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFF05A30),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isSaving || _isUploadingAvatar) ? null : _finalizeOnboarding,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF05A30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: (_isSaving || _isUploadingAvatar)
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Finish Setup',
                            style: GoogleFonts.firaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MAIN BENTO GRID DASHBOARD WIDGETS
  // ==========================================
  Widget _buildDashboardView() {
    if (_isLoadingDashboard) {
      return const Scaffold(
        backgroundColor: Color(0xFFF0EFEF),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF05A30),
          ),
        ),
      );
    }

    final activeTheme = ProfileThemeColors.getTheme(_profileData?['card_theme']);
    final displayName = _profileData?['display_name'] ?? 'Incognito User';
    final avatarUrlString = _profileData?['avatar_url'];
    final birthday = _profileData?['birthday'] ?? 'Not set';
    final phoneNumber = _profileData?['phone_number'] ?? 'Not set';
    final username = _profileData?['username'] ?? '';

    final instagram = _socialLinksData?['instagram'] ?? '';
    final linkedin = _socialLinksData?['linkedin'] ?? '';
    final github = _socialLinksData?['github'] ?? '';
    final spotify = _socialLinksData?['spotify'] ?? '';

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F0E13) : const Color(0xFFF0EFEF),
      appBar: AppBar(
        title: Text(
          _currentTab == 0
              ? 'Hexa Portal'
              : (_currentTab == 1
                  ? 'My Friends Network'
                  : (_currentTab == 2 ? 'Community Hub' : 'Class Schedule')),
          style: GoogleFonts.firaSans(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 1.0,
            color: isDarkMode ? Colors.white : const Color(0xFF1E1E1E),
          ),
        ),
        backgroundColor: isDarkMode ? const Color(0xFF0F0E13) : const Color(0xFFF0EFEF),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: isDarkMode ? Colors.white70 : const Color(0xFF1E1E1E)),
            onPressed: _signOut,
          )
        ],
      ),
      body: _currentTab == 0
          ? SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // BENTO GRID - ITEM 1: Large Identity Header Card (Full Width)
                  _buildBentoItem(
                    onTap: () {
                      // Allows re-entering onboarding step 2 if they tap their profile header to modify details
                      setState(() {
                        _onboardingStep = 2;
                        _onboardingComplete = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.02),
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
                                backgroundColor: isDarkMode ? const Color(0xFF1E1C24) : const Color(0xFFFDF0ED),
                                backgroundImage: avatarUrlString != null
                                    ? NetworkImage(avatarUrlString)
                                    : null,
                                child: avatarUrlString == null
                                    ? const Icon(Icons.person, size: 40, color: Color(0xFFF05A30))
                                    : null,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (_profileData?['is_admin'] == true) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: isDarkMode ? Colors.white12 : const Color(0xFF1E1E1E),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text('🗿', style: TextStyle(fontSize: 12)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'ADMIN',
                                                  style: GoogleFonts.firaSans(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: Text(
                                            displayName,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.firaSans(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: isDarkMode ? Colors.white : const Color(0xFF1E1E1E),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.cake_outlined, size: 14, color: Color(0xFFF05A30)),
                                        const SizedBox(width: 6),
                                        Text(
                                          birthday,
                                          style: GoogleFonts.firaSans(fontSize: 13, color: isDarkMode ? Colors.white54 : Colors.black54),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.phone_outlined, size: 14, color: Color(0xFFF05A30)),
                                        const SizedBox(width: 6),
                                        Text(
                                          phoneNumber,
                                          style: GoogleFonts.firaSans(fontSize: 13, color: isDarkMode ? Colors.white54 : Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_note_outlined,
                                color: isDarkMode ? Colors.white38 : Colors.black38,
                                size: 24,
                              )
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildBranchDetailsBanner(activeTheme),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUpcomingClassBentoItem(activeTheme),
                  const SizedBox(height: 16),                  // BENTO GRID - ITEM 2: Dedicated Plus Card Bento Button
                  _buildPlusCardBentoButton(username, displayName, phoneNumber, activeTheme, isDarkMode),
                  const SizedBox(height: 16),

                  // BENTO GRID - 2x2/3x2 Grid of Bento Squares
                  Row(
                    children: [
                      // Instagram Square
                      Expanded(
                        child: _buildBentoItem(
                          onTap: () => _launchSocialLink('instagram', instagram),
                          child: Container(
                            height: 180,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
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
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE1306C).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        color: Color(0xFFE1306C),
                                        size: 22,
                                      ),
                                    ),
                                    Icon(Icons.north_east_rounded, color: isDarkMode ? Colors.white30 : Colors.black26, size: 18),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Instagram',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 15,
                                        color: isDarkMode ? Colors.white54 : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      instagram.isNotEmpty ? '@$instagram' : 'Disconnect',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: instagram.isNotEmpty ? (isDarkMode ? Colors.white : const Color(0xFF1E1E1E)) : Colors.black38,
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // LinkedIn Square
                      Expanded(
                        child: _buildBentoItem(
                          onTap: () => _launchSocialLink('linkedin', linkedin),
                          child: Container(
                            height: 180,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
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
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0077B5).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.work_rounded,
                                        color: Color(0xFF0077B5),
                                        size: 22,
                                      ),
                                    ),
                                    Icon(Icons.north_east_rounded, color: isDarkMode ? Colors.white30 : Colors.black26, size: 18),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'LinkedIn',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 15,
                                        color: isDarkMode ? Colors.white54 : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      linkedin.isNotEmpty ? linkedin : 'Disconnect',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: linkedin.isNotEmpty ? (isDarkMode ? Colors.white : const Color(0xFF1E1E1E)) : Colors.black38,
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // GitHub Square
                      Expanded(
                        child: _buildBentoItem(
                          onTap: () => _launchSocialLink('github', github),
                          child: Container(
                            height: 180,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
                              gradient: RadialGradient(
                                colors: [
                                  (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.04),
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
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.code_rounded,
                                        color: isDarkMode ? Colors.white70 : const Color(0xFF1E1E1E),
                                        size: 22,
                                      ),
                                    ),
                                    Icon(Icons.north_east_rounded, color: isDarkMode ? Colors.white30 : Colors.black26, size: 18),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'GitHub',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 15,
                                        color: isDarkMode ? Colors.white54 : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      github.isNotEmpty ? github : 'Disconnect',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: github.isNotEmpty ? (isDarkMode ? Colors.white : const Color(0xFF1E1E1E)) : Colors.black38,
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Spotify Square
                      Expanded(
                        child: _buildBentoItem(
                          onTap: () => _launchSocialLink('spotify', spotify),
                          child: Container(
                            height: 180,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFF1DB954).withValues(alpha: 0.04),
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
                                    RotationTransition(
                                      turns: _vinylController,
                                      child: Container(
                                        width: 38,
                                        height: 38,
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
                                      ),
                                    ),
                                    Icon(Icons.north_east_rounded, color: isDarkMode ? Colors.white30 : Colors.black26, size: 18),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Spotify',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 15,
                                        color: isDarkMode ? Colors.white54 : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      spotify.isNotEmpty ? 'Soundtrack' : 'Not linked',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: spotify.isNotEmpty ? (isDarkMode ? Colors.white : const Color(0xFF1E1E1E)) : Colors.black38,
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Share Profile Square
                      Expanded(
                        child: _buildBentoItem(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            Clipboard.setData(ClipboardData(text: 'https://hexa.online/p/$username'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Profile link copied!'),
                                backgroundColor: activeTheme.primary,
                              ),
                            );
                          },
                          child: Container(
                            height: 180,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: activeTheme.primary.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        color: activeTheme.primary,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Profile Link',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 15,
                                        color: isDarkMode ? Colors.white54 : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Copy & Share',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode ? Colors.white : const Color(0xFF1E1E1E),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Appearance / Theme Toggle Square
                      Expanded(
                        child: _buildBentoItem(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            final current = HexaApp.themeNotifier.value;
                            HexaApp.themeNotifier.value = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                          },
                          child: Container(
                            height: 180,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5), width: 1.0),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: (isDarkMode ? Colors.amber : Colors.indigo).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isDarkMode ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                                        color: isDarkMode ? Colors.amber : Colors.indigo,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Appearance',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 15,
                                        color: isDarkMode ? Colors.white54 : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isDarkMode ? 'Dark Mode' : 'Light Mode',
                                      style: GoogleFonts.firaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode ? Colors.white : const Color(0xFF1E1E1E),
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
                  const SizedBox(height: 16),
                  // BENTO GRID - ITEM 2.5: Dynamic Profile Theme Selector Bento Item
                  _buildThemeSelectorBentoItem(activeTheme),
                  const SizedBox(height: 16),
                  const DevelopedByFooter(),
                ],
              ),
            )
          : (_currentTab == 1
              ? const FriendsTab()
              : (_currentTab == 2 ? const CommunityTab() : const ScheduleTab())),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() {
            _currentTab = index;
            if (index == 1) {
              _hasNewInviteNotification = false;
            } else if (index == 2) {
              _hasNewMessageNotification = false;
            }
          });
        },
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFF05A30),
        unselectedItemColor: Colors.black38,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: 'MY BENTO MATRIX',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.people_alt_rounded),
                if (_hasNewInviteNotification)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'MY FRIENDS',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.forum_rounded),
                if (_hasNewMessageNotification)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'COMMUNITY',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_rounded),
            label: 'CLASS SCHEDULE',
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingClassBentoItem(ProfileThemeColors activeTheme) {
    if (_scheduleItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final weekdayInt = now.weekday;
    String currentDay = 'Monday';
    switch (weekdayInt) {
      case DateTime.monday: currentDay = 'Monday'; break;
      case DateTime.tuesday: currentDay = 'Tuesday'; break;
      case DateTime.wednesday: currentDay = 'Wednesday'; break;
      case DateTime.thursday: currentDay = 'Thursday'; break;
      case DateTime.friday: currentDay = 'Friday'; break;
      case DateTime.saturday: currentDay = 'Saturday'; break;
      case DateTime.sunday: currentDay = 'Sunday'; break;
    }

    if (currentDay == 'Sunday') {
      return _buildUpcomingCardContainer(
        title: 'Sunday Study Break ☕',
        subtitle: 'No classes scheduled today! Enjoy your weekend!',
        progress: 0.0,
      );
    }

    final todayClasses = _scheduleItems.where((c) => c['day_of_week'] == currentDay).toList();

    if (todayClasses.isEmpty) {
      return _buildUpcomingCardContainer(
        title: 'No Classes Today 🎉',
        subtitle: 'You have a completely free schedule today.',
        progress: 0.0,
      );
    }

    final Map<int, List<int>> lectureTimes = {
      1: [9, 25, 10, 15],
      2: [10, 15, 11, 5],
      3: [11, 15, 12, 5],
      4: [12, 5, 12, 55],
      5: [13, 45, 14, 30],
      6: [14, 30, 15, 15],
      7: [15, 25, 16, 10],
      8: [16, 10, 16, 55],
      9: [16, 55, 17, 40],
    };

    Map<String, dynamic>? nextClass;
    int minutesRemaining = -1;
    double progress = 0.0;
    bool isCurrentlyRunning = false;

    for (final cls in todayClasses) {
      final idx = cls['lecture_index'] as int;
      final times = lectureTimes[idx];
      if (times == null) continue;

      final classStart = DateTime(now.year, now.month, now.day, times[0], times[1]);
      final classEnd = DateTime(now.year, now.month, now.day, times[2], times[3]);

      if (now.isBefore(classStart)) {
        final diff = classStart.difference(now).inMinutes;
        if (nextClass == null || diff < minutesRemaining) {
          nextClass = cls;
          minutesRemaining = diff;
          isCurrentlyRunning = false;
          if (diff <= 60) {
            progress = (60 - diff) / 60.0;
          } else {
            progress = 0.0;
          }
        }
      } else if (now.isAfter(classStart) && now.isBefore(classEnd)) {
        nextClass = cls;
        isCurrentlyRunning = true;
        final totalDuration = classEnd.difference(classStart).inMinutes;
        final elapsed = now.difference(classStart).inMinutes;
        progress = elapsed / totalDuration;
        minutesRemaining = classEnd.difference(now).inMinutes;
        break;
      }
    }

    if (nextClass == null) {
      return _buildUpcomingCardContainer(
        title: 'All Classes Finished 🎉',
        subtitle: 'No more lectures remaining for today!',
        progress: 1.0,
      );
    }

    final subject = nextClass['subject'] ?? '';
    final room = nextClass['room'] ?? '';
    final teacher = nextClass['teacher'] ?? '';
    final isRed = nextClass['is_red'] == true;

    String alertTitle;
    String alertSubtitle;

    if (isCurrentlyRunning) {
      alertTitle = 'Ongoing Class: $subject ⏳';
      alertSubtitle = 'Room $room ($minutesRemaining mins remaining)';
    } else {
      alertTitle = 'Next Class: $subject in $minutesRemaining mins';
      alertSubtitle = 'Room $room starts shortly${teacher.isNotEmpty ? ' with $teacher' : ''}';
    }

    return _buildUpcomingCardContainer(
      title: alertTitle,
      subtitle: alertSubtitle,
      progress: progress.clamp(0.0, 1.0),
      isHighPriority: isRed,
    );
  }

  Widget _buildUpcomingCardContainer({
    required String title,
    required String subtitle,
    required double progress,
    bool isHighPriority = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighPriority ? const Color(0xFFE53935) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isHighPriority ? const Color(0xFFC62828) : const Color(0xFFE5E5E5),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.alarm_on_rounded,
                size: 20,
                color: isHighPriority ? Colors.white70 : const Color(0xFFF05A30),
              ),
              const SizedBox(width: 8),
              Text(
                'CAMPUS PULSE SCHEDULE',
                style: GoogleFonts.firaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: isHighPriority ? Colors.white70 : Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.firaSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isHighPriority ? Colors.white : const Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.firaSans(
              fontSize: 13,
              color: isHighPriority ? Colors.white.withValues(alpha: 0.8) : Colors.black54,
            ),
          ),
          if (progress > 0.0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: isHighPriority
                    ? Colors.white.withValues(alpha: 0.2)
                    : const Color(0xFFFDF0ED),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isHighPriority ? Colors.white : const Color(0xFFF05A30),
                ),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlusCardBentoButton(String username, String name, String phoneNumber, ProfileThemeColors activeTheme, bool isDarkMode) {
    if (username.isEmpty) return const SizedBox.shrink();

    return _buildBentoItem(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlusCardScreen(
              name: name,
              username: username,
              phoneNumber: phoneNumber,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF16151A) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDarkMode ? const Color(0xFF2C2A35) : const Color(0xFFE5E5E5),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: activeTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.contactless_rounded,
                    color: activeTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plus Card',
                      style: GoogleFonts.firaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '3D NFC Profile Card',
                      style: GoogleFonts.firaSans(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: isDarkMode ? Colors.white30 : Colors.black26,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchDetailsBanner(ProfileThemeColors activeTheme) {
    final String? course = _profileData?['course'];
    final String? branch = _profileData?['branch'];
    final String? section = _profileData?['section'];

    final bool isSet = course != null && course.isNotEmpty;

    String bannerText = 'Add College Branch Details';
    if (isSet) {
      if (course == 'Btech' && branch != null && branch.isNotEmpty) {
        bannerText = 'B.Tech ($branch)';
      } else {
        bannerText = course;
      }
      if (section != null && section.isNotEmpty) {
        bannerText += ' | Section $section';
      }
    }

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const BranchDetailsEditScreen(),
          ),
        );
        if (result == true) {
          _loadDashboardData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: activeTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: activeTheme.primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSet ? Icons.school_rounded : Icons.school_outlined,
              color: activeTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                bannerText,
                style: GoogleFonts.firaSans(
                  color: isSet ? activeTheme.primary : Colors.black54,
                  fontSize: 14,
                  fontWeight: isSet ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: activeTheme.primary.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSelectorBentoItem(ProfileThemeColors activeTheme) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: activeTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  color: activeTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile Theme',
                      style: GoogleFonts.firaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Theme: ${activeTheme.name}',
                      style: GoogleFonts.firaSans(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ProfileThemeColors.themes.map((theme) {
              final isSelected = theme.id == activeTheme.id;
              return GestureDetector(
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  _updateCardTheme(theme.id);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? theme.primary : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [theme.primary, theme.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: theme.primary.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            )
                          ]
                        : [],
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}

  Future<void> _updateCardTheme(String themeId) async {
    if (_profileData != null) {
      setState(() {
        _profileData!['card_theme'] = themeId;
      });
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client
          .from('profiles')
          .update({'card_theme': themeId})
          .eq('id', userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to persist theme: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Bento Interactive Gesture Custom Wrapper
  Widget _buildBentoItem({required Widget child, required VoidCallback onTap}) {
    return _BentoHoverWrapper(
      onTap: onTap,
      child: child,
    );
  }

  void _setupRealtimeNotifications() {
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    if (myId == null) return;

    _cleanupRealtimeNotifications();
    _checkInitialNotificationBadges(myId);

    _connectionsChannel = client
        .channel('public:connections:receiver:$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'connections',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            if (record['status'] == 'pending') {
              final senderId = record['sender_id'] as String;
              final senderProfile = await client
                  .from('profiles')
                  .select('display_name, avatar_url, username')
                  .eq('id', senderId)
                  .maybeSingle();

              final senderName = senderProfile?['display_name'] ?? senderProfile?['username'] ?? 'Someone';
              final avatarUrl = senderProfile?['avatar_url'] as String?;

              setState(() {
                _hasNewInviteNotification = true;
              });

              _showInAppNotification(
                title: 'New Friend Invite',
                body: '$senderName wants to connect with you.',
                avatarUrl: avatarUrl,
                onTap: () {
                  setState(() {
                    _currentTab = 1;
                    _hasNewInviteNotification = false;
                  });
                },
              );
            }
          },
        )
        .subscribe();

    _messagesChannel = client
        .channel('public:messages:receiver:$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            final senderId = record['sender_id'] as String;
            final content = record['content'] as String;

            final senderProfile = await client
                .from('profiles')
                .select('display_name, avatar_url, username')
                .eq('id', senderId)
                .maybeSingle();

            final senderName = senderProfile?['display_name'] ?? senderProfile?['username'] ?? 'Someone';
            final avatarUrl = senderProfile?['avatar_url'] as String?;

            setState(() {
              _hasNewMessageNotification = true;
            });

            _showInAppNotification(
              title: senderName,
              body: content,
              avatarUrl: avatarUrl,
              onTap: () {
                setState(() {
                  _currentTab = 2;
                  _hasNewMessageNotification = false;
                });
              },
            );
          },
        )
        .subscribe();
  }

  void _cleanupRealtimeNotifications() {
    if (_connectionsChannel != null) {
      Supabase.instance.client.removeChannel(_connectionsChannel!);
      _connectionsChannel = null;
    }
    if (_messagesChannel != null) {
      Supabase.instance.client.removeChannel(_messagesChannel!);
      _messagesChannel = null;
    }
  }

  Future<void> _checkInitialNotificationBadges(String myId) async {
    try {
      final client = Supabase.instance.client;

      final pendingInvitesRes = await client
          .from('connections')
          .select('id')
          .eq('receiver_id', myId)
          .eq('status', 'pending');

      final unreadMessagesRes = await client
          .from('messages')
          .select('id')
          .eq('receiver_id', myId)
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          _hasNewInviteNotification = pendingInvitesRes.isNotEmpty;
          _hasNewMessageNotification = unreadMessagesRes.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('Error checking initial badges: $e');
    }
  }

  void _showInAppNotification({
    required String title,
    required String body,
    String? avatarUrl,
    required VoidCallback onTap,
  }) {
    if (!mounted) return;
    
    HapticFeedback.vibrate();

    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) {
        return _InAppNotificationWidget(
          title: title,
          body: body,
          avatarUrl: avatarUrl,
          onTap: () {
            overlayEntry.remove();
            onTap();
          },
          onDismiss: () {
            overlayEntry.remove();
          },
        );
      },
    );

    Overlay.of(context).insert(overlayEntry);
  }
}

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

class _InAppNotificationWidget extends StatefulWidget {
  final String title;
  final String body;
  final String? avatarUrl;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationWidget({
    required this.title,
    required this.body,
    this.avatarUrl,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationWidget> createState() => _InAppNotificationWidgetState();
}

class _InAppNotificationWidgetState extends State<_InAppNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack));

    _slideController.forward();

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (!mounted) return;
    _slideController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: SlideTransition(
            position: _slideAnimation,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  _slideController.reverse().then((_) {
                    widget.onTap();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE5E5E5), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFFDF0ED),
                        backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
                        child: widget.avatarUrl == null ? const Icon(Icons.person, color: Color(0xFFF05A30), size: 18) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.firaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E1E1E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.firaSans(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.black38, size: 18),
                        onPressed: _dismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
