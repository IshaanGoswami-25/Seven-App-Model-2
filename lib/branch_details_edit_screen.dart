import 'package:flutter/material.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BranchDetailsEditScreen extends StatefulWidget {
  const BranchDetailsEditScreen({super.key});

  @override
  State<BranchDetailsEditScreen> createState() => _BranchDetailsEditScreenState();
}

class _BranchDetailsEditScreenState extends State<BranchDetailsEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // State variables
  bool _isLoading = true;
  bool _isSaving = false;
  
  String? _selectedCourse;
  String? _selectedBranch;
  final _sectionController = TextEditingController();

  final List<String> _courses = ['Btech', 'BBA', 'BCA', 'MBA', 'B.Pharma'];
  final List<String> _branches = ['CS core', 'AI', 'AI&ML', 'CS DS', 'IT', 'ECE'];

  @override
  void initState() {
    super.initState();
    _loadAcademicDetails();
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _loadAcademicDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('course, branch, section')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          _selectedCourse = profile['course'];
          _selectedBranch = profile['branch'];
          _sectionController.text = profile['section'] ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load details: ${e.toString()}'),
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

  Future<void> _saveAcademicDetails() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // If course is not Btech, branch should be null
      final String? finalBranch = _selectedCourse == 'Btech' ? _selectedBranch : null;

      await Supabase.instance.client.from('profiles').update({
        'course': _selectedCourse,
        'branch': finalBranch,
        'section': _sectionController.text.trim().toUpperCase(),
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch details saved successfully!'),
            backgroundColor: Color(0xFFF05A30),
          ),
        );
        Navigator.of(context).pop(true); // Return true to signal reload
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
            ),
            title: Text(
              'Save Error',
              style: GoogleFonts.firaSans(
                color: const Color(0xFFF05A30),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              e.toString(),
              style: GoogleFonts.firaSans(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.87)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'College Branch Details',
          style: GoogleFonts.firaSans(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF05A30).withValues(alpha: 0.05),
              ),
            ),
          ),
          _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFF05A30),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24.0),
                    child: Container(
                      padding: EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Academic Profile details',
                              style: GoogleFonts.firaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E),
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Provide your college course, branch, and section details below to showcase on your bento matrix card.',
                              style: GoogleFonts.firaSans(fontSize: 14, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.54)),
                            ),
                            SizedBox(height: 32),

                            // Course Dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCourse,
                              dropdownColor: Colors.white,
                              style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                              decoration: InputDecoration(
                                labelText: 'Course / Degree',
                                prefixIcon: Icon(Icons.school_outlined, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45)),
                              ),
                              items: _courses.map((course) {
                                return DropdownMenuItem<String>(
                                  value: course,
                                  child: Text(course),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedCourse = val;
                                  // Reset branch if not Btech
                                  if (_selectedCourse != 'Btech') {
                                    _selectedBranch = null;
                                  }
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select a course';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 20),

                            // Branch Dropdown (Only visible for Btech)
                            if (_selectedCourse == 'Btech') ...[
                              DropdownButtonFormField<String>(
                                initialValue: _selectedBranch,
                                dropdownColor: Colors.white,
                                style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                                decoration: InputDecoration(
                                  labelText: 'B.Tech Specialization / Branch',
                                  prefixIcon: Icon(Icons.account_tree_outlined, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45)),
                                ),
                                items: _branches.map((branch) {
                                  return DropdownMenuItem<String>(
                                    value: branch,
                                    child: Text(branch),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedBranch = val;
                                  });
                                },
                                validator: (value) {
                                  if (_selectedCourse == 'Btech' && (value == null || value.isEmpty)) {
                                    return 'Please select a branch';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 20),
                            ],

                            // Section Input
                            TextFormField(
                              controller: _sectionController,
                              style: GoogleFonts.firaSans(color: Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xFF1E1E1E)),
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 5,
                              decoration: InputDecoration(
                                labelText: 'Section Code',
                                hintText: 'e.g. A, B, Sec-A',
                                prefixIcon: Icon(Icons.grid_3x3_outlined, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black).withValues(alpha: 0.45)),
                                counterText: '', // Hide default counter
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your section';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 40),

                            // Save Button
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                color: const Color(0xFFF05A30),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF05A30).withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isSaving ? null : _saveAcademicDetails,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: _isSaving
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Text(
                                        'Save Details',
                                        style: GoogleFonts.firaSans(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).cardTheme.color,
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
        ],
      ),
    );
  }
}
