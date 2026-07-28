import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'google_fonts_alias.dart';

class Interactive3DCard extends StatefulWidget {
  final String name;
  final String username;
  final String phoneNumber;
  final bool autoRotate;

  const Interactive3DCard({
    super.key,
    required this.name,
    required this.username,
    required this.phoneNumber,
    this.autoRotate = false,
  });

  @override
  State<Interactive3DCard> createState() => _Interactive3DCardState();
}

class _Interactive3DCardState extends State<Interactive3DCard> with TickerProviderStateMixin {
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  double _shineX = 0.5;
  double _shineY = 0.5;

  late AnimationController _resetController;
  late Animation<double> _resetAnimX;
  late Animation<double> _resetAnimY;
  AnimationController? _autoRotateController;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    if (widget.autoRotate) {
      _autoRotateController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 6),
      )..addListener(() {
        if (mounted && !_resetController.isAnimating) {
          final progress = _autoRotateController!.value * 2.0 * math.pi;
          setState(() {
            _tiltY = 0.6 * math.sin(progress);
            _tiltX = 0.15 * math.cos(progress);
            _shineX = 0.5 + 0.3 * math.sin(progress);
            _shineY = 0.5 + 0.3 * math.cos(progress);
          });
        }
      })..repeat();
    }
  }

  @override
  void dispose() {
    _resetController.dispose();
    _autoRotateController?.dispose();
    super.dispose();
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    if (_resetController.isAnimating) _resetController.stop();
    if (_autoRotateController != null && _autoRotateController!.isAnimating) {
      _autoRotateController!.stop();
    }

    final localPos = details.localPosition;
    final rx = (localPos.dx / size.width) - 0.5;
    final ry = (localPos.dy / size.height) - 0.5;

    setState(() {
      _tiltY = rx * 0.35;
      _tiltX = -ry * 0.35;
      _shineX = localPos.dx / size.width;
      _shineY = localPos.dy / size.height;
    });
  }

  void _handlePanEnd() {
    _resetAnimX = Tween<double>(begin: _tiltX, end: 0.0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic),
    );
    _resetAnimY = Tween<double>(begin: _tiltY, end: 0.0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic),
    );

    _resetController.addListener(_onResetTick);
    _resetController.forward(from: 0.0).then((_) {
      _resetController.removeListener(_onResetTick);
      if (widget.autoRotate && _autoRotateController != null) {
        _autoRotateController!.repeat();
      }
    });
  }

  void _onResetTick() {
    setState(() {
      _tiltX = _resetAnimX.value;
      _tiltY = _resetAnimY.value;
      // Smoothly return shine position to neutral center
      _shineX = 0.5 + (_tiltY / 0.35) * 0.5;
      _shineY = 0.5 - (_tiltX / 0.35) * 0.5;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Generate unique serial code based on username
    final cleanUsername = widget.username.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final serialSuffix = cleanUsername.length >= 4 
        ? cleanUsername.substring(0, 4).toUpperCase() 
        : cleanUsername.padRight(4, 'X').toUpperCase();
    final String serialCode = 'HX${serialSuffix}20';

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = width / 1.58; // Standard card aspect ratio (85.60 x 53.98)
        final size = Size(width, height);

        // Map pan coordinates to a shifting linear gradient direction
        final alignmentX = -1.5 + _shineX * 3.0; 
        final alignmentY = -1.5 + _shineY * 3.0;

        return GestureDetector(
          onPanUpdate: (details) => _handlePanUpdate(details, size),
          onPanEnd: (_) => _handlePanEnd(),
          onPanCancel: () => _handlePanEnd(),
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015) // Perspective distortion factor
              ..rotateX(_tiltX)
              ..rotateY(_tiltY),
            alignment: FractionalOffset.center,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE5A65D).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                image: const DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1519681393784-d120267933ba?q=80&w=800'),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black,
                    BlendMode.multiply,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    // Celestial/Moon glow path gradient overlay
                    Positioned(
                      top: -height * 0.2,
                      left: -width * 0.1,
                      child: Container(
                        width: width * 0.55,
                        height: width * 0.55,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFE5A65D).withValues(alpha: 0.25),
                              const Color(0xFFE5A65D).withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // specularity / 3D light reflection sheen
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(alignmentX - 0.4, alignmentY - 0.4),
                            end: Alignment(alignmentX + 0.4, alignmentY + 0.4),
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.25, 0.5, 0.75],
                          ),
                        ),
                      ),
                    ),

                    // Card Text & UI Details Layout
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. TOP ROW: NFC wave symbol + LIMITED EDITION Label
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // NFC Wave Symbol
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.sensors,
                                    color: Color(0xFFE5A65D),
                                    size: 24,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'NFC',
                                    style: GoogleFonts.firaSans(
                                      color: const Color(0xFFE5A65D),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),

                              // LIMITED EDITION Label
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'LIMITED EDITION',
                                    style: GoogleFonts.firaSans(
                                      color: const Color(0xFFE5A65D).withValues(alpha: 0.8),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '01/20',
                                    style: GoogleFonts.firaSans(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // 2. MIDDLE ROW: Plus Card ⚡ logo + QR Code
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Plus Card Logo stamp
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Plus Card ⚡',
                                    style: GoogleFonts.firaSans(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                  Text(
                                    'NFC SMART CARD',
                                    style: GoogleFonts.firaSans(
                                      color: const Color(0xFFE5A65D),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ],
                              ),

                              // QR Code block on the right
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: height * 0.35,
                                    height: height * 0.35,
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Image.network(
                                      'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=https://hexa.online/p/${widget.username}',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => const Icon(
                                        Icons.qr_code_2_rounded,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'TAP OR SCAN TO CONNECT',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.firaSans(
                                      color: Colors.white70,
                                      fontSize: 7,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // 3. BOTTOM ROW: User Details, Slogan + Serial Capsule
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Left: User details + Slogan
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.name.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '@${widget.username}  |  ${widget.phoneNumber}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaSans(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'YOUR IDENTITY. ONE TAP AWAY.',
                                      style: GoogleFonts.firaSans(
                                        color: const Color(0xFFE5A65D),
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Right: Serial code capsule
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE5A65D).withValues(alpha: 0.5),
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  serialCode,
                                  style: GoogleFonts.firaSans(
                                    color: const Color(0xFFE5A65D),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
