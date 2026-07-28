import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';
import 'developed_by_footer.dart';

class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // PDF Notes catalog states
  List<Map<String, dynamic>> _pdfNotes = [];
  bool _isLoadingNotes = true;
  
  // Chats list states
  List<Map<String, dynamic>> _recentChats = [];
  bool _isLoadingChats = true;
  
  // Discover list states
  List<Map<String, dynamic>> _discoverUsers = [];
  bool _isLoadingDiscover = true;
  String _searchQuery = '';

  String? _myUserId;
  bool _isAdmin = false;
  RealtimeChannel? _presenceChannel;
  Set<String> _onlineUserIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    
    _checkAdminStatus();
    _fetchPdfNotes();
    _fetchRecentChats();
    _fetchDiscoverUsers();
    _setupPresence();
  }

  Future<void> _checkAdminStatus() async {
    if (_myUserId == null) return;
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('is_admin')
          .eq('id', _myUserId!)
          .maybeSingle();
      if (response != null && mounted) {
        setState(() {
          _isAdmin = response['is_admin'] == true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_presenceChannel != null) {
      Supabase.instance.client.removeChannel(_presenceChannel!);
    }
    super.dispose();
  }

  void _setupPresence() {
    if (_myUserId == null) return;
    final client = Supabase.instance.client;

    _presenceChannel = client.channel('online-presence-lobby');

    _presenceChannel!.onPresenceSync((_) {
      final states = _presenceChannel!.presenceState();
      final Set<String> onlineIds = {};
      
      for (final state in states) {
        for (final presence in state.presences) {
          final payload = presence.payload;
          if (payload['user_id'] != null) {
            onlineIds.add(payload['user_id'].toString());
          }
        }
      }

      if (mounted) {
        setState(() {
          _onlineUserIds = onlineIds;
        });
      }
    });

    _presenceChannel!.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _presenceChannel!.track({
          'user_id': _myUserId,
          'online_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  // Fetch PDF Study Notes list
  Future<void> _fetchPdfNotes() async {
    if (!mounted) return;
    setState(() {
      _isLoadingNotes = true;
    });

    try {
      final client = Supabase.instance.client;
      // Fetch notes and join profile data
      final response = await client
          .from('community_pdf_notes')
          .select('*, profiles(username, display_name, avatar_url)')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pdfNotes = List<Map<String, dynamic>>.from(response);
          _isLoadingNotes = false;
        });
      }
    } catch (e) {
      _showError('Failed to load shared notes: ${e.toString()}');
      if (mounted) {
        setState(() {
          _isLoadingNotes = false;
        });
      }
    }
  }

  // Fetch Active Direct Message Logs
  Future<void> _fetchRecentChats() async {
    if (_myUserId == null) return;
    if (!mounted) return;
    setState(() {
      _isLoadingChats = true;
    });

    try {
      final client = Supabase.instance.client;
      // Query messages involving me
      final messages = await client
          .from('messages')
          .select()
          .or('sender_id.eq.$_myUserId,receiver_id.eq.$_myUserId')
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> lastMessages = {};
      for (var msg in messages) {
        final senderId = msg['sender_id'] as String;
        final receiverId = msg['receiver_id'] as String;
        final otherId = senderId == _myUserId ? receiverId : senderId;

        if (!lastMessages.containsKey(otherId)) {
          lastMessages[otherId] = msg;
        }
      }

      if (lastMessages.isEmpty) {
        if (mounted) {
          setState(() {
            _recentChats = [];
            _isLoadingChats = false;
          });
        }
        return;
      }

      final partnerIds = lastMessages.keys.toList();
      final partnerProfiles = await client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .inFilter('id', partnerIds);

      final List<Map<String, dynamic>> chatsList = [];
      final unreadCounts = await client
          .from('messages')
          .select('sender_id')
          .eq('receiver_id', _myUserId!)
          .eq('is_read', false);
      final unreadSenderIds = unreadCounts.map((m) => m['sender_id'] as String).toSet();

      for (var profile in partnerProfiles) {
        final partnerId = profile['id'] as String;
        final lastMsg = lastMessages[partnerId]!;
        final hasUnread = unreadSenderIds.contains(partnerId);
        chatsList.add({
          'user_id': partnerId,
          'username': profile['username'],
          'display_name': profile['display_name'],
          'avatar_url': profile['avatar_url'],
          'last_message': lastMsg['content'],
          'last_message_time': lastMsg['created_at'],
          'has_unread': hasUnread,
        });
      }

      chatsList.sort((a, b) => b['last_message_time'].compareTo(a['last_message_time']));

      if (mounted) {
        setState(() {
          _recentChats = chatsList;
          _isLoadingChats = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching chats: $e');
      if (mounted) {
        setState(() {
          _isLoadingChats = false;
        });
      }
    }
  }

  // Fetch all registered profiles for DM initiation (Discover tab)
  Future<void> _fetchDiscoverUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoadingDiscover = true;
    });

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('profiles')
          .select('id, username, display_name, avatar_url, course, branch')
          .order('display_name', ascending: true);

      if (mounted) {
        setState(() {
          // Filter out current user from discover search catalog
          _discoverUsers = List<Map<String, dynamic>>.from(response)
              .where((u) => u['id'] != _myUserId)
              .toList();
          _isLoadingDiscover = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading discover directory: $e');
      if (mounted) {
        setState(() {
          _isLoadingDiscover = false;
        });
      }
    }
  }

  // Launch browser or file reader to render PDF
  Future<void> _viewPdfNote(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not resolve browser link.';
      }
    } catch (e) {
      _showError('Failed to display PDF document: $e');
    }
  }

  Future<void> _confirmDeletePdfNote(String id, String fileUrl) async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
          ),
          title: Text(
            'Delete PDF Note?',
            style: GoogleFonts.firaSans(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to permanently delete this PDF note from the community hub?',
            style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.firaSans(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _deletePdfNote(id, fileUrl);
              },
              child: Text(
                'Delete',
                style: GoogleFonts.firaSans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePdfNote(String id, String fileUrl) async {
    setState(() {
      _isLoadingNotes = true;
    });

    try {
      final client = Supabase.instance.client;

      // 1. Delete from Supabase Table
      await client.from('community_pdf_notes').delete().eq('id', id);

      // 2. Delete from Storage Bucket
      try {
        final uri = Uri.parse(fileUrl);
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final fileName = pathSegments.last;
          await client.storage.from('pdf_notes').remove([fileName]);
        }
      } catch (_) {}

      HapticFeedback.mediumImpact();
      _fetchPdfNotes();
      _showSuccess('PDF note deleted successfully.');
    } catch (e) {
      _showError('Failed to delete note: ${e.toString()}');
      setState(() {
        _isLoadingNotes = false;
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // PDF Note Upload Controller trigger Dialog
  void _openUploadDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    
    Uint8List? selectedFileBytes;
    String? selectedFileName;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            // Picker helper
            Future<void> pickPdfFile() async {
              try {
                final FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                  withData: true,
                );

                if (result != null) {
                  final file = result.files.first;
                  final double fileSizeInMB = file.size / (1024 * 1024);
                  if (fileSizeInMB > 2.0) {
                    _showError('The selected PDF is ${fileSizeInMB.toStringAsFixed(2)}MB. Please select a PDF file below 2MB.');
                    return;
                  }

                  setDialogState(() {
                    selectedFileBytes = file.bytes;
                    selectedFileName = file.name;
                  });
                }
              } catch (e) {
                _showError('File picker error: ${e.toString()}');
              }
            }

            // PDF uploader logic
            Future<void> executeUpload() async {
              final title = titleController.text.trim();
              final desc = descController.text.trim();

              if (title.isEmpty) {
                _showError('Please enter a note title.');
                return;
              }
              if (selectedFileBytes == null) {
                _showError('Please select a PDF document.');
                return;
              }
              if (selectedFileBytes!.length > 2 * 1024 * 1024) {
                _showError('Selected PDF exceeds the 2MB size limit. Please reduce the size.');
                return;
              }

              setDialogState(() {
                isUploading = true;
              });

              try {
                final client = Supabase.instance.client;
                final userId = client.auth.currentUser!.id;
                
                final uniqueName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

                // 1. Upload file binary directly to public bucket 'pdf_notes'
                await client.storage.from('pdf_notes').uploadBinary(
                      uniqueName,
                      selectedFileBytes!,
                      fileOptions: const FileOptions(
                        contentType: 'application/pdf',
                        upsert: true,
                      ),
                    );

                // 2. Fetch public URL
                final publicUrl = client.storage.from('pdf_notes').getPublicUrl(uniqueName);

                // 3. Insert record in community_pdf_notes table
                await client.from('community_pdf_notes').insert({
                  'user_id': userId,
                  'title': title,
                  'description': desc,
                  'file_url': publicUrl,
                });

                if (!context.mounted) return;
                Navigator.of(context).pop(); // Dismiss upload dialog
                _fetchPdfNotes(); // Refresh note directory list
                _showSuccess('PDF notes uploaded and shared successfully!');
              } catch (e) {
                setDialogState(() {
                  isUploading = false;
                });
                _showError('Upload failed: ${e.toString()}');
              }
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
              ),
              title: Text(
                'Share Study Notes (PDF)',
                style: GoogleFonts.firaSans(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: titleController,
                      style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                      decoration: InputDecoration(
                        labelText: 'Notes Title',
                        hintText: 'e.g. Physics Unit 2 Notes',
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: descController,
                      style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Brief Description',
                        hintText: 'Add topics covered or key chapters...',
                      ),
                    ),
                    SizedBox(height: 24),

                    // File picker trigger
                    GestureDetector(
                      onTap: isUploading ? null : pickPdfFile,
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF0ED),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFF05A30).withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFF05A30),
                              size: 32,
                            ),
                            SizedBox(height: 8),
                            Text(
                              selectedFileName ?? 'Select PDF Document',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.firaSans(
                                color: const Color(0xFFF05A30),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54)),
                  ),
                ),
                ElevatedButton(
                  onPressed: isUploading ? null : executeUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF05A30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: isUploading
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Upload',
                          style: GoogleFonts.firaSans(color: Theme.of(context).cardTheme.color, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFF05A30),
        ),
      );
    }
  }

  // Launch search DM trigger dialog
  void _openDiscoverDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDiscoverState) {
            final filteredUsers = _discoverUsers.where((u) {
              final query = _searchQuery.toLowerCase();
              final displayName = (u['display_name'] ?? '').toString().toLowerCase();
              final username = (u['username'] ?? '').toString().toLowerCase();
              return displayName.contains(query) || username.contains(query);
            }).toList();

            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start Conversation',
                    style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                  ),
                  SizedBox(height: 12),
                  // Search query textfield
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextFormField(
                      style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E), fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search username or name...',
                        hintStyle: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 13),
                        prefixIcon: Icon(Icons.search, size: 18, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (val) {
                        setDiscoverState(() {
                          _searchQuery = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: _isLoadingDiscover
                    ? Center(child: CircularProgressIndicator(color: Color(0xFFF05A30)))
                    : filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              'No community members found.',
                              style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredUsers.length,
                            separatorBuilder: (context, index) => Divider(color: Theme.of(context).colorScheme.outline, height: 1),
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: const Color(0xFFFDF0ED),
                                      backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                                      child: user['avatar_url'] == null ? Icon(Icons.person, color: Color(0xFFF05A30), size: 16) : null,
                                    ),
                                    if (_onlineUserIds.contains(user['id']))
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Theme.of(context).cardTheme.color ?? Colors.white, width: 1.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(
                                  user['display_name'] ?? 'Community Member',
                                  style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E), fontSize: 14),
                                ),
                                subtitle: Text(
                                  '@${user['username']}',
                                  style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 12),
                                ),
                                trailing: Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFF05A30), size: 18),
                                onTap: () {
                                  Navigator.of(context).pop(); // Close discover dialog
                                  // Open DM Chat Screen
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => ChatScreen(
                                        otherUserId: user['id'],
                                        otherDisplayName: user['display_name'] ?? 'Incognito',
                                        otherUsername: user['username'] ?? '',
                                        otherAvatarUrl: user['avatar_url'],
                                      ),
                                    ),
                                  ).then((_) => _fetchRecentChats()); // Refresh recent chat logs on return
                                },
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDiscoverState(() {
                      _searchQuery = '';
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Close',
                    style: GoogleFonts.firaSans(color: const Color(0xFFF05A30), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Premium Custom Tab bar selectors
        Container(
          color: Theme.of(context).cardTheme.color,
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFF05A30),
            labelColor: const Color(0xFFF05A30),
            unselectedLabelColor: Colors.black38,
            labelStyle: GoogleFonts.firaSans(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(
                icon: Icon(Icons.menu_book_rounded, size: 20),
                text: 'STUDY NOTES (PDF)',
              ),
              Tab(
                icon: Icon(Icons.chat_rounded, size: 20),
                text: 'DIRECT MESSAGES',
              ),
            ],
          ),
        ),

        // Tabs Body Switcher
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // PANEL A: STUDY NOTES PDF DIRECTORY
              _buildNotesFeedTab(),

              // PANEL B: DIRECT MESSAGES INBOX LOGS
              _buildChatsInboxTab(),
            ],
          ),
        ),
      ],
    );
  }

  // 1. NOTES FEED COMPONENT VIEW
  Widget _buildNotesFeedTab() {
    return RefreshIndicator(
      onRefresh: _fetchPdfNotes,
      color: const Color(0xFFF05A30),
      backgroundColor: Theme.of(context).cardTheme.color,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: _isLoadingNotes
            ? Center(child: CircularProgressIndicator(color: Color(0xFFF05A30)))
            : _pdfNotes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.import_contacts_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 54),
                        SizedBox(height: 12),
                        Text(
                          'No notes have been shared yet.',
                          style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Be the first to upload and share study PDFs!',
                          style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.all(16.0),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: _pdfNotes.length,
                    itemBuilder: (context, index) {
                      final note = _pdfNotes[index];
                      final profile = note['profiles'] as Map<String, dynamic>? ?? {};
                      final String title = note['title'] ?? 'Untitled PDF';
                      final String desc = note['description'] ?? '';
                      final String fileUrl = note['file_url'] ?? '';

                      return Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // PDF Icon badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFDF0ED),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.picture_as_pdf_rounded,
                                        color: Color(0xFFF05A30),
                                        size: 20,
                                      ),
                                    ),
                                    // Uploader Profile avatar & optional Admin delete controls
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: const Color(0xFFFDF0ED),
                                          backgroundImage: profile['avatar_url'] != null ? NetworkImage(profile['avatar_url']) : null,
                                          child: profile['avatar_url'] == null ? Icon(Icons.person, color: Color(0xFFF05A30), size: 12) : null,
                                        ),
                                        if (_isAdmin) ...[
                                          SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _confirmDeletePdfNote(note['id'], fileUrl),
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.redAccent,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10),
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.firaSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  desc.isNotEmpty ? desc : 'No description provided.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.firaSans(
                                    fontSize: 11,
                                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54),
                                  ),
                                ),
                              ],
                            ),
                            // Action Button: Download/Read
                            ElevatedButton(
                              onPressed: () => _viewPdfNote(fileUrl),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF05A30),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: EdgeInsets.symmetric(vertical: 8),
                                elevation: 0,
                              ),
                              child: Text(
                                'Open PDF',
                                style: GoogleFonts.firaSans(color: Theme.of(context).cardTheme.color, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                      const DevelopedByFooter(),
                    ],
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openUploadDialog,
          backgroundColor: const Color(0xFFF05A30),
          elevation: 4,
          shape: const CircleBorder(),
          child: Icon(Icons.upload_file_rounded, color: Theme.of(context).cardTheme.color, size: 24),
        ),
      ),
    );
  }

  // 2. CHATS LIST INBOX COMPONENT VIEW
  Widget _buildChatsInboxTab() {
    return RefreshIndicator(
      onRefresh: _fetchRecentChats,
      color: const Color(0xFFF05A30),
      backgroundColor: Theme.of(context).cardTheme.color,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: _isLoadingChats
            ? Center(child: CircularProgressIndicator(color: Color(0xFFF05A30)))
            : _recentChats.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 54),
                        SizedBox(height: 12),
                        Text(
                          'No conversations started yet.',
                          style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Tapping the "+" icon below to find community members!',
                          style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.all(16),
                    itemCount: _recentChats.length,
                    separatorBuilder: (context, index) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final chat = _recentChats[index];
                      final lastMsgText = chat['last_message'] ?? '';

                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                otherUserId: chat['user_id'],
                                otherDisplayName: chat['display_name'] ?? 'Incognito',
                                otherUsername: chat['username'] ?? '',
                                otherAvatarUrl: chat['avatar_url'],
                              ),
                            ),
                          ).then((_) => _fetchRecentChats());
                        },
                        child: Container(
                          padding: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFFDF0ED),
                                    backgroundImage: chat['avatar_url'] != null ? NetworkImage(chat['avatar_url']) : null,
                                    child: chat['avatar_url'] == null ? Icon(Icons.person, color: Color(0xFFF05A30), size: 22) : null,
                                  ),
                                  if (_onlineUserIds.contains(chat['user_id']))
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Theme.of(context).cardTheme.color ?? Colors.white, width: 2.0),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              chat['display_name'] ?? 'Community Member',
                                              style: GoogleFonts.firaSans(
                                                color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (chat['has_unread'] == true) ...[
                                              SizedBox(width: 8),
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Icon(Icons.chevron_right, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 18),
                                      ],
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      lastMsgText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                      const DevelopedByFooter(),
                    ],
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openDiscoverDialog,
          backgroundColor: const Color(0xFFF05A30),
          elevation: 4,
          shape: const CircleBorder(),
          child: Icon(Icons.chat_bubble_rounded, color: Theme.of(context).cardTheme.color, size: 22),
        ),
      ),
    );
  }
}
