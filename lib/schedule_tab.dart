import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'developed_by_footer.dart';

const Map<int, String> lectureStartTimes = {
  1: "09.25",
  2: "10.15",
  3: "11.15",
  4: "12.05",
  5: "13.45",
  6: "14.30",
  7: "15.25",
  8: "16.10",
  9: "16.55",
};

const Map<int, String> lectureDisplayTimes = {
  1: "09:25 - 10:15",
  2: "10:15 - 11:05",
  3: "11:15 - 12:05",
  4: "12:05 - 12:55",
  5: "01:45 - 02:30",
  6: "02:30 - 03:15",
  7: "03:25 - 04:10",
  8: "04:10 - 04:55",
  9: "04:55 - 05:40",
};

class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  final List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  String _selectedDay = 'Monday';
  
  List<Map<String, dynamic>> _scheduleItems = [];
  bool _isLoading = true;
  String? _myUserId;

  // Controllers for Add/Edit Form dialog
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  bool _isRed = false;

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    _setTodayAsDefault();
    _fetchSchedule();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _roomController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  void _setTodayAsDefault() {
    final int weekday = DateTime.now().weekday;
    switch (weekday) {
      case DateTime.monday: _selectedDay = 'Monday'; break;
      case DateTime.tuesday: _selectedDay = 'Tuesday'; break;
      case DateTime.wednesday: _selectedDay = 'Wednesday'; break;
      case DateTime.thursday: _selectedDay = 'Thursday'; break;
      case DateTime.friday: _selectedDay = 'Friday'; break;
      case DateTime.saturday: _selectedDay = 'Saturday'; break;
      default: _selectedDay = 'Monday'; break;
    }
  }

  Future<void> _fetchSchedule() async {
    if (_myUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('class_schedule')
          .select()
          .eq('user_id', _myUserId!)
          .order('lecture_index', ascending: true);

      final List<Map<String, dynamic>> fetchedItems = List<Map<String, dynamic>>.from(response);

      if (fetchedItems.isEmpty) {
        // Automatically seed with default template from image
        await _seedDefaultSchedule(_myUserId!);
        
        // Re-fetch
        final reResponse = await client
            .from('class_schedule')
            .select()
            .eq('user_id', _myUserId!)
            .order('lecture_index', ascending: true);
            
        if (mounted) {
          setState(() {
            _scheduleItems = List<Map<String, dynamic>>.from(reResponse);
            _isLoading = false;
          });
          _syncAlarms();
        }
      } else {
        if (mounted) {
          setState(() {
            _scheduleItems = fetchedItems;
            _isLoading = false;
          });
          _syncAlarms();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showError('Failed to load schedule: ${e.toString()}');
      }
    }
  }

  Future<void> _syncAlarms() async {
    try {
      // 1. Cancel all scheduled alarms to clean up
      await NotificationService.cancelAllNotifications();
      // 2. Request runtime alert permissions
      await NotificationService.requestPermissions();

      // 3. Reschedule alerts for all class slots (5 mins before start time)
      for (final item in _scheduleItems) {
        final int index = item['lecture_index'];
        final String? startStr = lectureStartTimes[index];
        if (startStr != null) {
          await NotificationService.scheduleClassNotification(
            id: item['id'] as String,
            subject: item['subject'] as String,
            room: item['room'] as String,
            weekday: item['day_of_week'] as String,
            timeString: startStr,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _saveClass(int lectureIndex, String? existingId) async {
    final subject = _subjectController.text.trim();
    final room = _roomController.text.trim();
    final teacher = _teacherController.text.trim();

    if (subject.isEmpty || room.isEmpty || _myUserId == null) {
      _showError('Subject Code and Room Number are required.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final client = Supabase.instance.client;
      final payload = {
        'user_id': _myUserId!,
        'day_of_week': _selectedDay,
        'lecture_index': lectureIndex,
        'subject': subject,
        'room': room,
        'teacher': teacher,
        'is_red': _isRed,
      };

      if (existingId != null) {
        payload['id'] = existingId;
      }

      await client.from('class_schedule').upsert(payload);
      HapticFeedback.mediumImpact();
      _fetchSchedule();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Failed to save slot: ${e.toString()}');
    }
  }

  Future<void> _deleteClass(String id) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.from('class_schedule').delete().eq('id', id);
      HapticFeedback.mediumImpact();
      _fetchSchedule();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Failed to delete slot: ${e.toString()}');
    }
  }

  Future<void> _seedDefaultSchedule(String userId) async {
    final defaultClasses = [
      // Monday
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 1, 'subject': 'CS-304', 'room': 'AA-13', 'teacher': 'Hritik Mandal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 2, 'subject': 'CS-301', 'room': 'AA-13', 'teacher': 'Chandra Shekhar Tiwari', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 3, 'subject': 'TT-FSD-301', 'room': 'F-34', 'teacher': 'Rajesh Kumar Pandey', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 4, 'subject': 'TT-FSD-301', 'room': 'F-34', 'teacher': 'Rajesh Kumar Pandey', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 5, 'subject': 'VT-301', 'room': 'E-14', 'teacher': 'Rajeev Dayal Singh', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 6, 'subject': 'VT-301', 'room': 'E-14', 'teacher': 'Rajeev Dayal Singh', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 7, 'subject': 'TT-H-3', 'room': 'P-21-22', 'teacher': 'Anil Yadav', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Monday', 'lecture_index': 8, 'subject': 'TT-H-3', 'room': 'P-22-23', 'teacher': 'Anil Yadav', 'is_red': false},

      // Tuesday
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 1, 'subject': 'VT-301', 'room': 'E-14', 'teacher': 'Balu Sankar', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 2, 'subject': 'VT-301', 'room': 'E-14', 'teacher': 'Balu Sankar', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 3, 'subject': 'TT-HT-3', 'room': 'AA-13', 'teacher': 'Upasana Dugal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 4, 'subject': 'TT-HT-3', 'room': 'AA-13', 'teacher': 'Upasana Dugal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 5, 'subject': 'CS-301', 'room': 'E-14', 'teacher': 'Chandra Shekhar Tiwari', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 6, 'subject': 'BS-303', 'room': 'E-14', 'teacher': 'Sameera Iqram', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 7, 'subject': 'TT-DA-3', 'room': 'F-12', 'teacher': 'Nayancy', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Tuesday', 'lecture_index': 8, 'subject': 'TT-DA-3', 'room': 'F-12', 'teacher': 'Nayancy', 'is_red': false},

      // Wednesday
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 1, 'subject': 'CS-301', 'room': 'K-24', 'teacher': 'Chandra Shekhar Tiwari', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 2, 'subject': 'BS-303', 'room': 'K-24', 'teacher': 'Sameera Iqram', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 3, 'subject': 'TT-HD-3', 'room': 'E-12', 'teacher': 'Upasana Dugal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 4, 'subject': 'TT-HD-3', 'room': 'E-12', 'teacher': 'Upasana Dugal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 5, 'subject': 'TR-OLT-301', 'room': 'P-21-22', 'teacher': 'Preeti Sharma', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 6, 'subject': 'TR-OLT-301', 'room': 'P-22-23', 'teacher': 'Preeti Sharma', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 7, 'subject': 'CS-354', 'room': 'AA-13', 'teacher': 'Hritik Mandal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Wednesday', 'lecture_index': 8, 'subject': 'CS-354', 'room': 'AA-13', 'teacher': 'Hritik Mandal', 'is_red': false},

      // Thursday (marked as red / high-priority matching image highlight)
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 1, 'subject': 'CS-304', 'room': 'M-11', 'teacher': 'Hritik Mandal', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 2, 'subject': 'VA-301', 'room': 'M-11', 'teacher': 'Chhavi Mishra Jha', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 3, 'subject': 'TT-FSD-301', 'room': 'F-34', 'teacher': 'Rajesh Kumar Pandey', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 4, 'subject': 'TT-FSD-301', 'room': 'F-34', 'teacher': 'Rajesh Kumar Pandey', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 5, 'subject': 'CS-302', 'room': 'AA-13', 'teacher': 'Durgesh Pandey', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 6, 'subject': 'CS-302', 'room': 'AA-13', 'teacher': 'Durgesh Pandey', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 7, 'subject': 'TT-DBMS-301', 'room': 'AA-13', 'teacher': 'Arya Raj', 'is_red': true},
      {'user_id': userId, 'day_of_week': 'Thursday', 'lecture_index': 8, 'subject': 'TT-DBMS-301', 'room': 'AA-13', 'teacher': 'Arya Raj', 'is_red': true},

      // Friday
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 1, 'subject': 'CS-352 [B]', 'room': 'B-31', 'teacher': 'Ruchi Agarwal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 2, 'subject': 'CS-352 [B]', 'room': 'B-31', 'teacher': 'Ruchi Agarwal', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 3, 'subject': 'CS-301', 'room': 'AA-13', 'teacher': 'Chandra Shekhar Tiwari', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 4, 'subject': 'BS-303', 'room': 'AA-13', 'teacher': 'Sameera Iqram', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 5, 'subject': 'TT-DA-3', 'room': 'AA-13', 'teacher': 'Nayancy', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 6, 'subject': 'TT-DA-3', 'room': 'AA-13', 'teacher': 'Nayancy', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 7, 'subject': 'CS-302', 'room': 'AA-13', 'teacher': 'Durgesh Pandey', 'is_red': false},
      {'user_id': userId, 'day_of_week': 'Friday', 'lecture_index': 8, 'subject': 'BS-303', 'room': 'AA-13', 'teacher': 'Sameera Iqram', 'is_red': false},
    ];

    try {
      await Supabase.instance.client.from('class_schedule').insert(defaultClasses);
    } catch (_) {}
  }

  void _openAddDialog(int lectureIndex) {
    _subjectController.clear();
    _roomController.clear();
    _teacherController.clear();
    _isRed = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Add Lecture ${_getOrdinal(lectureIndex)} Slot',
                style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _subjectController,
                      decoration: InputDecoration(labelText: 'Course / Subject Code'),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _roomController,
                      decoration: InputDecoration(labelText: 'Room Number'),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _teacherController,
                      decoration: InputDecoration(labelText: 'Instructor Name'),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _isRed,
                          activeColor: const Color(0xFFF05A30),
                          onChanged: (val) {
                            setDialogState(() {
                              _isRed = val ?? false;
                            });
                          },
                        ),
                        Text(
                          'Mark as Red (High Priority / Lab)',
                          style: GoogleFonts.firaSans(fontSize: 13, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text('Cancel', style: GoogleFonts.firaSans(color: Colors.grey)),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF05A30),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Text('Save', style: GoogleFonts.firaSans(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    _saveClass(lectureIndex, null);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openEditDialog(Map<String, dynamic> item) {
    _subjectController.text = item['subject'] ?? '';
    _roomController.text = item['room'] ?? '';
    _teacherController.text = item['teacher'] ?? '';
    _isRed = item['is_red'] == true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Edit Lecture ${_getOrdinal(item['lecture_index'])} Slot',
                style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _subjectController,
                      decoration: InputDecoration(labelText: 'Course / Subject Code'),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _roomController,
                      decoration: InputDecoration(labelText: 'Room Number'),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _teacherController,
                      decoration: InputDecoration(labelText: 'Instructor Name'),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _isRed,
                          activeColor: const Color(0xFFF05A30),
                          onChanged: (val) {
                            setDialogState(() {
                              _isRed = val ?? false;
                            });
                          },
                        ),
                        Text(
                          'Mark as Red (High Priority / Lab)',
                          style: GoogleFonts.firaSans(fontSize: 13, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text('Delete', style: GoogleFonts.firaSans(color: Colors.redAccent)),
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteClass(item['id']);
                  },
                ),
                TextButton(
                  child: Text('Cancel', style: GoogleFonts.firaSans(color: Colors.grey)),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF05A30),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Text('Update', style: GoogleFonts.firaSans(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    _saveClass(item['lecture_index'], item['id']);
                  },
                ),
              ],
            );
          },
        );
      },
    );
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

  String _getOrdinal(int value) {
    if (value == 1) return '1st';
    if (value == 2) return '2nd';
    if (value == 3) return '3rd';
    return '${value}th';
  }

  Widget _buildDaySelector() {
    return Container(
      height: 50,
      margin: EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: _weekdays.length,
        itemBuilder: (context, index) {
          final day = _weekdays[index];
          final isSelected = day == _selectedDay;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDay = day;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: 10),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF05A30) : Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isSelected ? const Color(0xFFF05A30) : const Color(0xFFE5E5E5),
                  width: 1.0,
                ),
              ),
              child: Text(
                day,
                style: GoogleFonts.firaSans(
                  color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildClassCard(Map<String, dynamic> classItem) {
    final isRed = classItem['is_red'] == true;
    final subject = classItem['subject'] ?? '';
    final room = classItem['room'] ?? '';
    final teacher = classItem['teacher'] ?? '';

    return GestureDetector(
      onTap: () => _openEditDialog(classItem),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRed ? const Color(0xFFE53935) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isRed ? const Color(0xFFC62828) : const Color(0xFFE5E5E5),
            width: 1.0,
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
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  subject,
                  style: GoogleFonts.firaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isRed ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                  ),
                ),
                if (isRed)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'HIGH PRIORITY',
                      style: GoogleFonts.firaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).cardTheme.color,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 14,
                  color: isRed ? Colors.white70 : Colors.black45,
                ),
                SizedBox(width: 4),
                Text(
                  'Room $room',
                  style: GoogleFonts.firaSans(
                    fontSize: 12,
                    color: isRed ? Colors.white.withValues(alpha: 0.9) : Colors.black54,
                  ),
                ),
                if (teacher.isNotEmpty) ...[
                  SizedBox(width: 16),
                  Icon(
                    Icons.person_rounded,
                    size: 14,
                    color: isRed ? Colors.white70 : Colors.black45,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      teacher,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaSans(
                        fontSize: 12,
                        color: isRed ? Colors.white.withValues(alpha: 0.9) : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(int lectureIndex) {
    return GestureDetector(
      onTap: () => _openAddDialog(lectureIndex),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.26), size: 18),
            SizedBox(width: 6),
            Text(
              'Add Lecture Class...',
              style: GoogleFonts.firaSans(
                fontSize: 13,
                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.38),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassTimeline() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
      itemCount: 9,
      itemBuilder: (context, idx) {
        final lectureIndex = idx + 1;
        final timeDisplay = lectureDisplayTimes[lectureIndex] ?? "";
        
        final classItem = _scheduleItems.firstWhere(
          (item) => item['day_of_week'] == _selectedDay && item['lecture_index'] == lectureIndex,
          orElse: () => {},
        );

        final hasClass = classItem.isNotEmpty;

        return Container(
          margin: EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_getOrdinal(lectureIndex)} Lecture',
                        style: GoogleFonts.firaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFF05A30),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        timeDisplay,
                        style: GoogleFonts.firaSans(
                          fontSize: 11,
                          color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: hasClass
                    ? _buildClassCard(classItem)
                    : _buildEmptyCard(lectureIndex),
              ),
            ],
          ),
        );
      },
    ),
        const DevelopedByFooter(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFF05A30),
                ),
              )
            : Column(
                children: [
                  _buildDaySelector(),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: _buildClassTimeline(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
