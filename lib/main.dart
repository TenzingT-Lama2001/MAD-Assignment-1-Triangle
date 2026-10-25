// =============================================================================
// NIT6120 Mobile Apps Development (MAD) - Assignment 1: Triangles
// Student: Tenzing (s8186470)
//
// A single-screen Flutter app that:
//   1. lets the user enter the length of each side of a triangle,
//   2. when "Type ?" is pressed, tells the user:
//        - whether the three lengths can form a triangle,
//        - whether it is equilateral, isosceles or scalene, and
//        - whether the triangle contains a right angle,
//   3. draws the triangle on screen in proportion to the entered lengths, and
//   4. rotates the drawing continuously in 3 dimensions, showing a different
//      colour (pink) on the reverse side of the triangle.
//
// Classes in this file:
//   TriangleApp          - root widget, sets up MaterialApp and the theme
//   TriangleType         - enum of the three triangle types
//   TriangleAnalysis     - pure Dart "model": all the triangle maths
//   TriangleScreen       - the single screen (StatefulWidget)
//   _TriangleScreenState - screen state: inputs, results, rotation animation
//   RotatingTriangle     - applies the 3D rotation and picks front/back colour
//   TrianglePainter      - CustomPainter that draws the proportional triangle
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colour of the front face of the drawn triangle.
const Color kFrontColour = Color(0xFF81D4FA); // light blue

/// Colour of the back (reverse) face of the drawn triangle.
const Color kBackColour = Color(0xFFF48FB1); // pink

/// Entry point. runApp() makes TriangleApp the root of the widget tree.
void main() => runApp(const TriangleApp());

// -----------------------------------------------------------------------------
// ROOT WIDGET
// Stateless because nothing here changes: it only sets up the Material app,
// the colour theme and the home screen.
// -----------------------------------------------------------------------------
class TriangleApp extends StatelessWidget {
  const TriangleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Triangles',
      debugShowCheckedModeBanner: false, // hide the red DEBUG banner
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const TriangleScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// MODEL: triangle maths
// Kept separate from the UI so the logic is easy to read, test and explain.
// Sides are integers, so every check below is exact (no rounding errors).
// -----------------------------------------------------------------------------

/// The three possible triangle types.
enum TriangleType { equilateral, isosceles, scalene }

/// Holds three side lengths and answers every question the app asks about
/// them: is it a triangle, what type is it, does it have a right angle, and
/// what are its interior angles.
class TriangleAnalysis {
  final int a; // length of side A
  final int b; // length of side B
  final int c; // length of side C

  const TriangleAnalysis(this.a, this.b, this.c);

  /// Triangle inequality theorem: the sum of any two sides must be greater
  /// than the third side. If not, the sides cannot meet to close a triangle.
  bool get isValid => a + b > c && a + c > b && b + c > a;

  /// If the sides fail the triangle inequality, explains which check failed,
  /// e.g. "1 + 2 is not greater than 10". Returns null for a valid triangle.
  String? get failureReason {
    if (a + b <= c) return '$a + $b is not greater than $c';
    if (a + c <= b) return '$a + $c is not greater than $b';
    if (b + c <= a) return '$b + $c is not greater than $a';
    return null;
  }

  /// Equilateral = all three sides equal, isosceles = exactly two equal,
  /// scalene = no two sides equal.
  TriangleType get type {
    if (a == b && b == c) return TriangleType.equilateral;
    if (a == b || b == c || a == c) return TriangleType.isosceles;
    return TriangleType.scalene;
  }

  /// Human-readable name and meaning of the triangle type.
  String get typeDescription => switch (type) {
        TriangleType.equilateral => 'Equilateral (all three sides are equal)',
        TriangleType.isosceles => 'Isosceles (two sides are equal)',
        TriangleType.scalene => 'Scalene (no two sides are equal)',
      };

  /// The three sides sorted from shortest to longest.
  List<int> get _sortedSides => [a, b, c]..sort();

  /// Pythagoras' theorem: the triangle has a right angle if the squares of
  /// the two shorter sides add up to the square of the longest side.
  /// Because the inputs are integers, this comparison is exact.
  bool get isRightAngled {
    final s = _sortedSides;
    return s[0] * s[0] + s[1] * s[1] == s[2] * s[2];
  }

  /// Shows the working for the right-angle check, e.g. "3² + 4² = 5²".
  String get pythagorasWorking {
    final s = _sortedSides;
    final symbol = isRightAngled ? '=' : '≠';
    return '${s[0]}² + ${s[1]}² $symbol ${s[2]}²';
  }

  /// Interior angles in degrees, using the law of cosines.
  /// Index 0 is the angle opposite side A, 1 opposite B, 2 opposite C.
  List<double> get anglesInDegrees {
    // Angle opposite side `opp`, between sides `x` and `y`.
    double angle(int opp, int x, int y) {
      final cosValue = (x * x + y * y - opp * opp) / (2 * x * y);
      // clamp() guards against tiny floating point errors outside [-1, 1]
      return math.acos(cosValue.clamp(-1.0, 1.0)) * 180 / math.pi;
    }

    return [angle(a, b, c), angle(b, a, c), angle(c, a, b)];
  }
}

// -----------------------------------------------------------------------------
// THE SCREEN
// Stateful because the results, the drawing and the rotation all change
// while the app is running.
// -----------------------------------------------------------------------------
class TriangleScreen extends StatefulWidget {
  const TriangleScreen({super.key});

  @override
  State<TriangleScreen> createState() => _TriangleScreenState();
}

class _TriangleScreenState extends State<TriangleScreen>
    with SingleTickerProviderStateMixin {
  // SingleTickerProviderStateMixin provides the "ticker" (a callback once per
  // screen frame) that drives the AnimationController below.

  // Controllers let the code read and clear the three input fields.
  final TextEditingController _sideAController = TextEditingController();
  final TextEditingController _sideBController = TextEditingController();
  final TextEditingController _sideCController = TextEditingController();

  /// Result of the last "Type ?" press. Null before the first press or
  /// after Clear.
  TriangleAnalysis? _analysis;

  /// Error shown when an input is empty or zero.
  String? _inputError;

  /// Drives the rotation. Its value goes from 0.0 to 1.0 once per full turn
  /// and then repeats, so the triangle rotates continuously.
  late final AnimationController _rotationController;

  /// True while the triangle is rotating.
  bool _isRotating = false;

  /// Rotation speed multiplier chosen with the slider (1.0 = normal).
  double _speed = 1.0;

  /// Time for one full turn at normal (1.0x) speed.
  static const int _baseTurnMilliseconds = 6000;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _baseTurnMilliseconds),
    );
  }

  @override
  void dispose() {
    // Release resources when the screen is removed.
    _sideAController.dispose();
    _sideBController.dispose();
    _sideCController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUTTON ACTIONS
  // ---------------------------------------------------------------------------

  /// "Type ?" button: reads the three sides, analyses them and, if they form
  /// a triangle, draws it and starts it rotating.
  void _onTypePressed() {
    FocusScope.of(context).unfocus(); // hide the keyboard

    final a = int.tryParse(_sideAController.text);
    final b = int.tryParse(_sideBController.text);
    final c = int.tryParse(_sideCController.text);

    // Every side must be a whole number greater than zero.
    if (a == null || b == null || c == null || a <= 0 || b <= 0 || c <= 0) {
      _stopRotation();
      setState(() {
        _analysis = null;
        _inputError = 'Please enter a whole number greater than 0 '
            'for every side.';
      });
      return;
    }

    final analysis = TriangleAnalysis(a, b, c);
    setState(() {
      _inputError = null;
      _analysis = analysis;
    });

    // Rotate only when there is a triangle to draw.
    if (analysis.isValid) {
      _rotationController.value = 0; // start each new triangle face-on
      _startRotation();
    } else {
      _stopRotation();
    }
  }

  /// "Clear" button: empties the inputs, removes the results and the drawing,
  /// and stops the rotation.
  void _onClearPressed() {
    FocusScope.of(context).unfocus();
    _sideAController.clear();
    _sideBController.clear();
    _sideCController.clear();
    _stopRotation();
    _rotationController.value = 0;
    setState(() {
      _analysis = null;
      _inputError = null;
      _speed = 1.0;
    });
  }

  /// Start/Stop button under the triangle.
  void _onToggleRotationPressed() {
    _isRotating ? _stopRotation() : _startRotation();
  }

  // ---------------------------------------------------------------------------
  // ROTATION HELPERS
  // ---------------------------------------------------------------------------

  /// Starts (or restarts) the rotation at the current speed.
  /// repeat() continues from the current angle, so there is no jump.
  void _startRotation() {
    _rotationController.duration = _turnDuration();
    _rotationController.repeat();
    setState(() => _isRotating = true);
  }

  /// Stops the rotation where it is. The triangle keeps its current angle.
  void _stopRotation() {
    _rotationController.stop();
    if (_isRotating) setState(() => _isRotating = false);
  }

  /// Speed slider moved: store the new speed and, if rotating, apply it
  /// straight away.
  void _onSpeedChanged(double value) {
    setState(() => _speed = value);
    if (_isRotating) {
      _rotationController.duration = _turnDuration();
      _rotationController.repeat(); // continue from the current angle
    }
  }

  /// Duration of one full turn: faster speed means a shorter duration.
  Duration _turnDuration() =>
      Duration(milliseconds: (_baseTurnMilliseconds / _speed).round());

  // ---------------------------------------------------------------------------
  // BUILD THE UI
  // Flutter calls build() again every time setState() is called.
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    final showTriangle = analysis != null && analysis.isValid;

    return Scaffold(
      // HEADER: larger font than every other label on the screen.
      appBar: AppBar(
        title: const Text(
          'Triangles',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),

      // BODY: scrolls so nothing is cut off when the keyboard is open.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the length of each side, then press "Type ?".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),

            // Three side-length inputs in one row.
            Row(
              children: [
                Expanded(child: _sideField('Side A', _sideAController)),
                const SizedBox(width: 8),
                Expanded(child: _sideField('Side B', _sideBController)),
                const SizedBox(width: 8),
                Expanded(child: _sideField('Side C', _sideCController)),
              ],
            ),
            const SizedBox(height: 16),

            // "Type ?" and "Clear" buttons, centred under the inputs.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: _onTypePressed,
                  child: const Text('Type ?', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _onClearPressed,
                  child: const Text('Clear', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Answers to the three questions.
            _resultsCard(analysis),
            const SizedBox(height: 16),

            // The drawn triangle (or a placeholder until there is one).
            Center(
              child: showTriangle
                  ? RotatingTriangle(
                      animation: _rotationController,
                      analysis: analysis!, // not null when showTriangle
                      size: 260,
                    )
                  : _placeholderBox(),
            ),

            // Rotation controls, shown under the triangle.
            if (showTriangle) ...[
              const SizedBox(height: 8),
              _colourLegend(),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _onToggleRotationPressed,
                  icon: Icon(_isRotating ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    _isRotating ? 'Stop rotation' : 'Start rotation',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Rotation speed: ${_speed.toStringAsFixed(2)}x',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              Slider(
                value: _speed,
                min: 0.25,
                max: 3.0,
                divisions: 11, // steps of 0.25
                label: '${_speed.toStringAsFixed(2)}x',
                onChanged: _onSpeedChanged,
              ),
            ],
          ],
        ),
      ),

      // FOOTER: student name and ID, smaller than every other label.
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Tenzing  |  s8186470',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SMALL UI HELPERS (avoid repeating the same widget code)
  // ---------------------------------------------------------------------------

  /// One labelled side-length input that only accepts whole numbers.
  Widget _sideField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly, // digits only, no decimals
        LengthLimitingTextInputFormatter(6), // keeps the numbers sensible
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// Card showing the answers: can the sides form a triangle, which type is
  /// it, and does it have a right angle.
  Widget _resultsCard(TriangleAnalysis? analysis) {
    final List<Widget> rows;

    if (_inputError != null) {
      rows = [_resultRow('Error', _inputError!, Colors.red)];
    } else if (analysis == null) {
      rows = [
        const Text(
          'Results will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.black54),
        ),
      ];
    } else if (!analysis.isValid) {
      rows = [
        _resultRow(
          'Can these sides form a triangle?',
          'No: ${analysis.failureReason}.',
          Colors.red,
        ),
      ];
    } else {
      final angles = analysis.anglesInDegrees;
      rows = [
        _resultRow('Can these sides form a triangle?', 'Yes', Colors.green),
        const SizedBox(height: 10),
        _resultRow('Type', analysis.typeDescription),
        const SizedBox(height: 10),
        _resultRow(
          'Does it contain a right angle?',
          analysis.isRightAngled
              ? 'Yes (${analysis.pythagorasWorking})'
              : 'No (${analysis.pythagorasWorking})',
        ),
        const SizedBox(height: 10),
        _resultRow(
          'Interior angles',
          'A ${angles[0].toStringAsFixed(1)}°,  '
              'B ${angles[1].toStringAsFixed(1)}°,  '
              'C ${angles[2].toStringAsFixed(1)}°',
        ),
      ];
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }

  /// One question/answer pair inside the results card.
  Widget _resultRow(String question, String answer, [Color? answerColour]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question,
            style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(
          answer,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: answerColour,
          ),
        ),
      ],
    );
  }

  /// Grey box shown where the triangle will be drawn.
  Widget _placeholderBox() {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Text(
        'No triangle drawn yet',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
    );
  }

  /// Small key explaining the two face colours.
  Widget _colourLegend() {
    Widget item(Color colour, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(kFrontColour, 'Front face'),
        const SizedBox(width: 20),
        item(kBackColour, 'Back face'),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 3D ROTATION
// Rebuilds every frame of the animation, rotating the drawing in 3D and
// choosing the front or back colour depending on which side faces the viewer.
// -----------------------------------------------------------------------------
class RotatingTriangle extends StatelessWidget {
  /// Animation value from 0.0 to 1.0, one full turn per cycle.
  final Animation<double> animation;

  /// The (valid) triangle to draw.
  final TriangleAnalysis analysis;

  /// Width and height of the drawing area.
  final double size;

  const RotatingTriangle({
    super.key,
    required this.animation,
    required this.analysis,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final turn = animation.value * 2 * math.pi; // 0 to 2π radians

        // Spin fully around the vertical (Y) axis, while tilting back and
        // forth around the horizontal (X) axis. sin() returns to the same
        // value at the end of each turn, so the loop is seamless.
        final angleY = turn;
        final angleX = 0.5 * math.sin(turn); // up to about 29° of tilt

        // Pure rotation (no perspective).
        final rotation = Matrix4.identity()
          ..rotateY(angleY)
          ..rotateX(angleX);

        // Back-face check: rotate the triangle's surface normal (0, 0, 1)
        // and look at its z component, which is entry (2, 2) of the matrix.
        // Positive = front faces the viewer, negative = back faces the viewer.
        final isFrontFacing = rotation.entry(2, 2) >= 0;

        // Add perspective so the nearer edge looks bigger than the far edge,
        // which is what makes the rotation look 3D instead of flat.
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..multiply(rotation);

        return Transform(
          alignment: Alignment.center, // rotate around the centre of the box
          transform: transform,
          child: CustomPaint(
            size: Size(size, size),
            painter: TrianglePainter(
              a: analysis.a.toDouble(),
              b: analysis.b.toDouble(),
              c: analysis.c.toDouble(),
              fillColour: isFrontFacing ? kFrontColour : kBackColour,
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// DRAWING
// Draws a triangle with the same proportions as the entered sides, scaled to
// fit and centred in the drawing area.
// -----------------------------------------------------------------------------
class TrianglePainter extends CustomPainter {
  final double a; // side A (opposite corner A)
  final double b; // side B (opposite corner B)
  final double c; // side C (opposite corner C)
  final Color fillColour;

  TrianglePainter({
    required this.a,
    required this.b,
    required this.c,
    required this.fillColour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Step 1: place the corners in "real" units.
    // Corner A sits at the origin and side C runs along the x-axis to
    // corner B. Corner C is found with the law of cosines, which gives the
    // angle at corner A from the three side lengths.
    final cosA = (b * b + c * c - a * a) / (2 * b * c);
    final sinA = math.sqrt(math.max(0.0, 1 - cosA * cosA));

    const ax = 0.0, ay = 0.0; // corner A
    final bx = c, by = 0.0; // corner B
    final cx = b * cosA, cy = -b * sinA; // corner C (negative y = upwards)

    // Step 2: bounding box of the triangle.
    final minX = math.min(ax, math.min(bx, cx));
    final maxX = math.max(ax, math.max(bx, cx));
    final minY = math.min(ay, math.min(by, cy));
    final maxY = math.max(ay, math.max(by, cy));
    final width = maxX - minX;
    final height = maxY - minY;

    // Step 3: one uniform scale for both x and y, so the shape keeps the
    // same proportions as the entered sides. 0.85 leaves a margin so the
    // corners are not clipped while rotating.
    final scale = math.min(size.width / width, size.height / height) * 0.85;

    // Step 4: shift so the triangle is centred in the drawing area.
    final dx = (size.width - width * scale) / 2 - minX * scale;
    final dy = (size.height - height * scale) / 2 - minY * scale;
    Offset toScreen(double x, double y) => Offset(x * scale + dx, y * scale + dy);

    final path = Path()
      ..moveTo(toScreen(ax, ay).dx, toScreen(ax, ay).dy)
      ..lineTo(toScreen(bx, by).dx, toScreen(bx, by).dy)
      ..lineTo(toScreen(cx, cy).dx, toScreen(cx, cy).dy)
      ..close();

    // Fill with the front or back colour, then draw a dark outline.
    canvas.drawPath(path, Paint()..color = fillColour);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Repaint only when the shape or the colour changes.
  @override
  bool shouldRepaint(covariant TrianglePainter oldDelegate) {
    return oldDelegate.a != a ||
        oldDelegate.b != b ||
        oldDelegate.c != c ||
        oldDelegate.fillColour != fillColour;
  }
}
