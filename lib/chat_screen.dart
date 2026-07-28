import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherDisplayName;
  final String otherUsername;
  final String? otherAvatarUrl;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.otherUsername,
    this.otherAvatarUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String? _myUserId;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _typingChannel;
  bool _otherUserIsTyping = false;
  Timer? _typingTimer;
  bool _iAmTyping = false;

  Map<String, dynamic>? _replyingToMessage;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    _fetchMessages();
    _subscribeToMessages();
    _subscribeToTyping();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
    if (_typingChannel != null) {
      Supabase.instance.client.removeChannel(_typingChannel!);
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fetch Message History
  Future<void> _fetchMessages() async {
    if (_myUserId == null) return;

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('messages')
          .select()
          .or('and(sender_id.eq.$_myUserId,receiver_id.eq.${widget.otherUserId}),and(sender_id.eq.${widget.otherUserId},receiver_id.eq.$_myUserId)')
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
        _scrollToBottom();
      }

      // Mark incoming messages as read
      await client
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', widget.otherUserId)
          .eq('receiver_id', _myUserId!)
          .eq('is_read', false);
    } catch (e) {
      _showError('Failed to load message history: ${e.toString()}');
    }
  }

  String _getChatRoomChannelName() {
    final ids = [_myUserId ?? '', widget.otherUserId];
    ids.sort();
    return 'chat_room_${ids[0]}_${ids[1]}';
  }

  void _subscribeToTyping() {
    if (_myUserId == null) return;
    final client = Supabase.instance.client;
    final roomName = _getChatRoomChannelName();

    _typingChannel = client.channel(roomName);

    _typingChannel!.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final userId = payload['user_id'] as String?;
        final isTyping = payload['is_typing'] as bool? ?? false;
        if (userId != _myUserId && mounted) {
          setState(() {
            _otherUserIsTyping = isTyping;
          });
        }
      },
    );

    _typingChannel!.subscribe();
  }

  void _onTextChanged(String text) {
    if (_typingChannel == null || _myUserId == null) return;

    if (!_iAmTyping) {
      _iAmTyping = true;
      _typingChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _myUserId, 'is_typing': true},
      );
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_iAmTyping && mounted) {
        _iAmTyping = false;
        _typingChannel!.sendBroadcastMessage(
          event: 'typing',
          payload: {'user_id': _myUserId, 'is_typing': false},
        );
      }
    });
  }

  Widget _buildTypingIndicator() {
    if (!_otherUserIsTyping) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      alignment: Alignment.centerLeft,
      color: Colors.transparent,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _otherUserIsTyping ? 1.0 : 0.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.otherDisplayName} is typing',
                    style: GoogleFonts.firaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54),
                    ),
                  ),
                  SizedBox(width: 6),
                  const _TypingDots(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Real-time update subscription
  void _subscribeToMessages() {
    final client = Supabase.instance.client;
    
    _realtimeChannel = client.channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              final newRecord = payload.newRecord;
              final senderId = newRecord['sender_id'] as String;
              final receiverId = newRecord['receiver_id'] as String;

              // Trigger fetch only if the message is in our current DM session
              if ((senderId == _myUserId && receiverId == widget.otherUserId) ||
                  (senderId == widget.otherUserId && receiverId == _myUserId)) {
                _fetchMessages();

                // Mark as read in background if sent to me
                if (senderId == widget.otherUserId && receiverId == _myUserId) {
                  client
                      .from('messages')
                      .update({'is_read': true})
                      .eq('id', newRecord['id'])
                      .then((_) {});
                }
              }
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final oldRecord = payload.oldRecord;
              final deletedId = oldRecord['id'];
              if (deletedId != null) {
                if (mounted) {
                  setState(() {
                    _messages.removeWhere((m) => m['id'] == deletedId);
                  });
                }
              }
            }
          },
        )
        .subscribe();
  }

  // Send Direct Message
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _myUserId == null) return;

    _typingTimer?.cancel();
    if (_iAmTyping && _typingChannel != null) {
      _iAmTyping = false;
      _typingChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _myUserId, 'is_typing': false},
      );
    }

    final Map<String, dynamic> insertData = {
      'sender_id': _myUserId,
      'receiver_id': widget.otherUserId,
      'content': text,
    };

    if (_replyingToMessage != null) {
      insertData['reply_to_id'] = _replyingToMessage!['id'];
    }

    _messageController.clear();
    setState(() {
      _replyingToMessage = null;
    });
    HapticFeedback.lightImpact();

    try {
      final client = Supabase.instance.client;
      await client.from('messages').insert(insertData);
      // Subscription callback handles updating list, but let's scroll down to ensure responsiveness
      _scrollToBottom();
    } catch (e) {
      _showError('Message send failed: ${e.toString()}');
    }
  }

  void _scrollToMessage(String msgId) {
    final key = _messageKeys[msgId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      
      setState(() {
        _highlightedMessageId = msgId;
      });
      
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && _highlightedMessageId == msgId) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    }
  }

  Widget _buildReplyPreviewInBubble(Map<String, dynamic> msg, bool isMe) {
    final replyToId = msg['reply_to_id'];
    if (replyToId == null) return const SizedBox.shrink();

    final originalMsg = _messages.firstWhere(
      (m) => m['id'] == replyToId,
      orElse: () => {},
    );

    if (originalMsg.isEmpty) {
      return Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.white70 : const Color(0xFFF05A30),
              width: 3,
            ),
          ),
        ),
        child: Text(
          'Deleted message',
          style: GoogleFonts.firaSans(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isMe ? Colors.white70 : Colors.black45,
          ),
        ),
      );
    }

    final originalIsMe = originalMsg['sender_id'] == _myUserId;
    final senderName = originalIsMe ? 'You' : widget.otherDisplayName;

    return GestureDetector(
      onTap: () => _scrollToMessage(replyToId),
      child: Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.white70 : const Color(0xFFF05A30),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName,
              style: GoogleFonts.firaSans(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isMe ? Colors.white : const Color(0xFFF05A30),
              ),
            ),
            SizedBox(height: 2),
            Text(
              originalMsg['content'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.firaSans(
                fontSize: 12,
                color: isMe ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(Map<String, dynamic> msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    msg['content'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.firaSans(
                      fontSize: 14,
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              Divider(height: 24),
              ListTile(
                leading: Icon(Icons.reply_rounded, color: Color(0xFFF05A30)),
                title: Text('Reply', style: GoogleFonts.firaSans(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingToMessage = msg;
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_rounded, color: Colors.redAccent),
                title: Text('Delete message', style: GoogleFonts.firaSans(color: Colors.redAccent, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMessage(msg);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteMessage(Map<String, dynamic> msg) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Delete Message?', style: GoogleFonts.firaSans(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to delete this message? This action cannot be undone.', style: GoogleFonts.firaSans()),
          actions: [
            TextButton(
              child: Text('Cancel', style: GoogleFonts.firaSans(color: Colors.grey)),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Delete', style: GoogleFonts.firaSans(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                _deleteMessage(msg['id']);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      final client = Supabase.instance.client;
      await client.from('messages').delete().eq('id', messageId);
      
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == messageId);
        });
      }
      HapticFeedback.mediumImpact();
    } catch (e) {
      _showError('Failed to delete message: ${e.toString()}');
    }
  }

  Widget _buildReplyPreviewBar() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final isMe = _replyingToMessage!['sender_id'] == _myUserId;
    final senderName = isMe ? 'You' : widget.otherDisplayName;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFF7F7F7),
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF05A30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: GoogleFonts.firaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFF05A30),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  _replyingToMessage!['content'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaSans(
                    fontSize: 13,
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54)),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardTheme.color,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFFDF0ED),
              backgroundImage: widget.otherAvatarUrl != null ? NetworkImage(widget.otherAvatarUrl!) : null,
              child: widget.otherAvatarUrl == null ? Icon(Icons.person, color: Color(0xFFF05A30), size: 18) : null,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.firaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                    ),
                  ),
                  Text(
                    '@${widget.otherUsername}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.firaSans(
                      fontSize: 11,
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFF05A30),
                      ),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.forum_outlined, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 48),
                              SizedBox(height: 12),
                              Text(
                                'Start of your Direct Message log',
                                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45), fontSize: 14),
                              ),
                              Text(
                                'Say hello to @${widget.otherUsername}!',
                                style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.all(20.0),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg['sender_id'] == _myUserId;
                            final DateTime timestamp = DateTime.parse(msg['created_at']).toLocal();
                            final String formattedTime = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
                            
                            final msgId = msg['id'] as String;
                            final itemKey = _messageKeys.putIfAbsent(msgId, () => GlobalKey());

                            return SwipeToReply(
                              key: ValueKey(msgId),
                              onReply: () {
                                setState(() {
                                  _replyingToMessage = msg;
                                });
                              },
                              child: Align(
                                key: itemKey,
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: GestureDetector(
                                  onLongPress: () => _showMessageOptions(msg),
                                  child: Container(
                                    margin: EdgeInsets.only(bottom: 12),
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _highlightedMessageId == msgId
                                                ? (isMe ? const Color(0xFFC84520) : const Color(0xFFFFE0D6))
                                                : (isMe ? const Color(0xFFF05A30) : Colors.white),
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(20),
                                              topRight: const Radius.circular(20),
                                              bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                                              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.02),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              )
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildReplyPreviewInBubble(msg, isMe),
                                              Text(
                                                msg['content'] ?? '',
                                                style: GoogleFonts.firaSans(
                                                  color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                                          child: Text(
                                            formattedTime,
                                            style: GoogleFonts.firaSans(
                                              color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38),
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Typing Indicator
            _buildTypingIndicator(),

            // Reply Preview Bar
            _buildReplyPreviewBar(),

            // Message Input Bar
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextFormField(
                        controller: _messageController,
                        onChanged: _onTextChanged,
                        style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                        textInputAction: TextInputAction.send,
                        onFieldSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38), fontSize: 14),
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFFF05A30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.send_rounded,
                        color: Theme.of(context).cardTheme.color,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom widget to handle swipe-to-reply gestures
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragOffset = 0.0;
  bool _thresholdReached = false;
  static const double _replyThreshold = 70.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.addListener(() {
      setState(() {
        _dragOffset = _controller.value * _dragOffset;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    if (details.delta.dx < 0 && _dragOffset <= 0) return;

    setState(() {
      _dragOffset += details.delta.dx * 0.6; // resistance
      if (_dragOffset < 0) _dragOffset = 0;
      if (_dragOffset > _replyThreshold * 1.5) _dragOffset = _replyThreshold * 1.5;

      if (_dragOffset >= _replyThreshold) {
        if (!_thresholdReached) {
          _thresholdReached = true;
          HapticFeedback.mediumImpact();
        }
      } else {
        _thresholdReached = false;
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_thresholdReached) {
      widget.onReply();
    }
    _thresholdReached = false;
    _controller.value = 1.0;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: -50,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 100),
              opacity: _dragOffset > 10 ? (_dragOffset / _replyThreshold).clamp(0.0, 1.0) : 0.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _thresholdReached ? const Color(0xFFF05A30) : Colors.black12,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.reply_rounded,
                  color: _thresholdReached ? Colors.white : Colors.black54,
                  size: 16,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final double value = (_controller.value + (index * 0.2)) % 1.0;
            final double offset = -3.0 * (1.0 - (value - 0.5).abs() * 2.0).clamp(0.0, 1.0);
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 1.5),
              transform: Matrix4.translationValues(0.0, offset, 0.0),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
