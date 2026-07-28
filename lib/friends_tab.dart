import 'package:flutter/material.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'public_profile_view_screen.dart';
import 'developed_by_footer.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  bool _isLoading = true;
  String? _myUserId;

  // Connection Lists
  List<Map<String, dynamic>> _pendingInvites = [];
  List<Map<String, dynamic>> _friendsList = [];

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    _fetchFriendsData();
  }

  Future<void> _fetchFriendsData() async {
    if (_myUserId == null) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final client = Supabase.instance.client;

      // 1. Fetch Pane A: Pending invites (where receiver is current user and status is 'pending')
      final pendingConnections = await client
          .from('connections')
          .select()
          .eq('receiver_id', _myUserId!)
          .eq('status', 'pending');

      List<Map<String, dynamic>> tempPending = [];
      if (pendingConnections.isNotEmpty) {
        final senderIds = pendingConnections.map((c) => c['sender_id'] as String).toList();
        final senderProfiles = await client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', senderIds);

        // Join connections and profiles
        for (var conn in pendingConnections) {
          final profile = senderProfiles.firstWhere(
            (p) => p['id'] == conn['sender_id'],
            orElse: () => <String, dynamic>{},
          );
          if (profile.isNotEmpty) {
            tempPending.add({
              'connection_id': conn['id'],
              'sender_id': conn['sender_id'],
              'username': profile['username'],
              'display_name': profile['display_name'],
              'avatar_url': profile['avatar_url'],
            });
          }
        }
      }

      // 2. Fetch Pane B: Friends Grid List (where sender OR receiver is current user and status is 'accepted')
      final acceptedConnections = await client
          .from('connections')
          .select()
          .or('sender_id.eq.$_myUserId,receiver_id.eq.$_myUserId')
          .eq('status', 'accepted');

      List<Map<String, dynamic>> tempFriends = [];
      if (acceptedConnections.isNotEmpty) {
        final friendIds = acceptedConnections
            .map((c) => c['sender_id'] == _myUserId ? c['receiver_id'] as String : c['sender_id'] as String)
            .toList();

        final friendProfiles = await client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', friendIds);

        for (var profile in friendProfiles) {
          final conn = acceptedConnections.firstWhere(
            (c) => c['sender_id'] == profile['id'] || c['receiver_id'] == profile['id'],
          );
          tempFriends.add({
            'connection_id': conn['id'],
            'friend_id': profile['id'],
            'username': profile['username'],
            'display_name': profile['display_name'],
            'avatar_url': profile['avatar_url'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _pendingInvites = tempPending;
          _friendsList = tempFriends;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading directory: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptRequest(String connectionId) async {
    try {
      final client = Supabase.instance.client;
      await client.from('connections').update({'status': 'accepted'}).eq('id', connectionId);
      _fetchFriendsData(); // Refresh list
    } catch (e) {
      _showError('Accept request failed: ${e.toString()}');
    }
  }

  Future<void> _declineRequest(String connectionId) async {
    try {
      final client = Supabase.instance.client;
      await client.from('connections').delete().eq('id', connectionId);
      _fetchFriendsData(); // Refresh list
    } catch (e) {
      _showError('Decline request failed: ${e.toString()}');
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

  void _openAddFriendsDialog() {
    if (_myUserId == null) return;
    showDialog(
      context: context,
      builder: (context) => _AddFriendsDialog(
        myUserId: _myUserId!,
        onRefreshParent: _fetchFriendsData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF05A30),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFriendsData,
      color: const Color(0xFFF05A30),
      backgroundColor: Theme.of(context).cardTheme.color,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // PANE A: PENDING INVITES
            _buildSectionHeader('PENDING INVITES (${_pendingInvites.length})'),
            SizedBox(height: 12),
            if (_pendingInvites.isEmpty)
              Container(
                padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                ),
                child: Text(
                  'No pending invites.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 14),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingInvites.length,
                separatorBuilder: (context, index) => SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final invite = _pendingInvites[index];
                  return Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFFFDF0ED),
                          backgroundImage: invite['avatar_url'] != null ? NetworkImage(invite['avatar_url']) : null,
                          child: invite['avatar_url'] == null ? Icon(Icons.person, color: Color(0xFFF05A30)) : null,
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invite['display_name'] ?? 'Anonymous',
                                style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E), fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '@${invite['username']}',
                                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.close, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), size: 22),
                              onPressed: () => _declineRequest(invite['connection_id']),
                            ),
                            SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.check, color: Color(0xFFF05A30), size: 22),
                              onPressed: () => _acceptRequest(invite['connection_id']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            SizedBox(height: 28),

            // PANE B: FRIENDS GRID LIST
            _buildSectionHeader(
              'MY CONNECTIONS (${_friendsList.length})',
              trailing: IconButton(
                icon: Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFF05A30), size: 22),
                onPressed: _openAddFriendsDialog,
                tooltip: 'Add Friends',
              ),
            ),
            SizedBox(height: 12),
            if (_friendsList.isEmpty)
              Container(
                padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 48),
                    SizedBox(height: 12),
                    Text(
                      'No friends connected yet.',
                      style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Scan a profile NFC tag to connect instantly!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _friendsList.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.25,
                ),
                itemBuilder: (context, index) {
                  final friend = _friendsList[index];
                  return GestureDetector(
                    onTap: () {
                      // Seamless Forward Navigation to Public Profile View
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => PublicProfileViewScreen(username: friend['username']),
                        ),
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFFDF0ED),
                                backgroundImage: friend['avatar_url'] != null ? NetworkImage(friend['avatar_url']) : null,
                                child: friend['avatar_url'] == null ? Icon(Icons.person, color: Color(0xFFF05A30), size: 18) : null,
                              ),
                              Icon(Icons.chevron_right, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 18),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                friend['display_name'] ?? 'Friend',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E), fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '@${friend['username']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 12),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            SizedBox(height: 16),
            const DevelopedByFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: EdgeInsets.only(left: 4.0, right: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.firaSans(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF05A30),
              letterSpacing: 1.5,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _AddFriendsDialog extends StatefulWidget {
  final String myUserId;
  final VoidCallback onRefreshParent;

  const _AddFriendsDialog({
    required this.myUserId,
    required this.onRefreshParent,
  });

  @override
  State<_AddFriendsDialog> createState() => _AddFriendsDialogState();
}

class _AddFriendsDialogState extends State<_AddFriendsDialog> {
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _userConnections = [];
  bool _loadingUsers = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchAddFriendsData();
  }

  Future<void> _fetchAddFriendsData() async {
    try {
      final client = Supabase.instance.client;
      final profilesRes = await client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .order('display_name');
      final connectionsRes = await client
          .from('connections')
          .select()
          .or('sender_id.eq.${widget.myUserId},receiver_id.eq.${widget.myUserId}');

      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(profilesRes)
              .where((u) => u['id'] != widget.myUserId)
              .toList();
          _userConnections = List<Map<String, dynamic>>.from(connectionsRes);
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load user directory: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequest(String targetUserId) async {
    if (mounted) {
      setState(() {
        _loadingUsers = true;
      });
    }
    try {
      final client = Supabase.instance.client;
      await client.from('connections').insert({
        'sender_id': widget.myUserId,
        'receiver_id': targetUserId,
        'status': 'pending',
      });
      widget.onRefreshParent();
      await _fetchAddFriendsData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send friend request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _acceptRequest(String connectionId) async {
    if (mounted) {
      setState(() {
        _loadingUsers = true;
      });
    }
    try {
      final client = Supabase.instance.client;
      await client.from('connections').update({'status': 'accepted'}).eq('id', connectionId);
      widget.onRefreshParent();
      await _fetchAddFriendsData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Accept request failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _allUsers.where((u) {
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
            'Add Friends',
            style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
          ),
          SizedBox(height: 12),
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
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: _loadingUsers
            ? Center(child: CircularProgressIndicator(color: Color(0xFFF05A30)))
            : filteredUsers.isEmpty
                ? Center(
                    child: Text(
                      'No users found.',
                      style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38)),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredUsers.length,
                    separatorBuilder: (context, index) => Divider(color: Theme.of(context).colorScheme.outline, height: 1),
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      final userId = user['id'] as String;

                      final connection = _userConnections.firstWhere(
                        (c) => (c['sender_id'] == widget.myUserId && c['receiver_id'] == userId) ||
                               (c['sender_id'] == userId && c['receiver_id'] == widget.myUserId),
                        orElse: () => <String, dynamic>{},
                      );

                      Widget actionWidget;
                      if (connection.isEmpty) {
                        actionWidget = ElevatedButton(
                          onPressed: () => _sendFriendRequest(userId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF05A30),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('Add', style: GoogleFonts.firaSans(fontSize: 12, fontWeight: FontWeight.bold)),
                        );
                      } else {
                        final status = connection['status'] as String;
                        final senderId = connection['sender_id'] as String;

                        if (status == 'accepted') {
                          actionWidget = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFFF05A30), size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Friends',
                                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          );
                        } else {
                          if (senderId == widget.myUserId) {
                            actionWidget = Text(
                              'Pending',
                              style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 12, fontWeight: FontWeight.w600),
                            );
                          } else {
                            actionWidget = ElevatedButton(
                              onPressed: () => _acceptRequest(connection['id']),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('Accept', style: GoogleFonts.firaSans(fontSize: 12, fontWeight: FontWeight.bold)),
                            );
                          }
                        }
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFFDF0ED),
                          backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                          child: user['avatar_url'] == null ? Icon(Icons.person, color: Color(0xFFF05A30), size: 16) : null,
                        ),
                        title: Text(
                          user['display_name'] ?? 'Anonymous',
                          style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E), fontSize: 14),
                        ),
                        subtitle: Text(
                          '@${user['username']}',
                          style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54), fontSize: 12),
                        ),
                        trailing: actionWidget,
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: GoogleFonts.firaSans(color: const Color(0xFFF05A30), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
