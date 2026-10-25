# Triangles

NIT6120 Mobile Apps Development (MAD), Assignment 1
Tenzing (s8186470), Victoria University Sydney

A single-screen Flutter/Dart app that analyses a triangle from its three side
lengths and draws it rotating in 3D.

## Features

- Three input fields for the side lengths (whole numbers only).
- **Type ?** button that reports:
  - whether the three lengths can form a triangle (triangle inequality), and
    if not, which check failed;
  - whether the triangle is equilateral, isosceles or scalene;
  - whether it contains a right angle (Pythagoras' theorem, with the working
    shown, e.g. 3² + 4² = 5²);
  - the three interior angles (law of cosines).
- The triangle is drawn in proportion to the entered sides, scaled to fit and
  centred on screen.
- The drawing rotates continuously in 3D (a full turn around the Y axis with a
  tilt around the X axis, plus perspective). The front face is light blue and
  the back face is pink.
- Start/Stop rotation button and a speed slider under the triangle.
- **Clear** button that resets the inputs, results and drawing.
- Footer with the student's name and ID.

## How to run

Requirements: Flutter SDK (stable channel) and an Android emulator or iOS
simulator.

```
cd triangles
flutter pub get
flutter run
```

Or open the `triangles` folder in VS Code, pick a device in the status bar and
press F5.

## Sample data to try

| Sides | Expected result |
|---|---|
| 3, 4, 5 | Valid, scalene, right angle (3² + 4² = 5²) |
| 5, 5, 5 | Valid, equilateral, no right angle |
| 5, 5, 8 | Valid, isosceles, no right angle |
| 7, 9, 12 | Valid, scalene, no right angle |
| 1, 2, 10 | Invalid: 1 + 2 is not greater than 10 |

## Code structure (`lib/main.dart`)

| Class | Purpose |
|---|---|
| `TriangleApp` | Root widget. Sets up `MaterialApp`, the theme and the home screen. |
| `TriangleType` | Enum: equilateral, isosceles, scalene. |
| `TriangleAnalysis` | Pure Dart model with all the maths: validity, type, right angle, interior angles. |
| `TriangleScreen` / `_TriangleScreenState` | The screen. Holds the input controllers, the current analysis, and the `AnimationController` that drives the rotation. Handles the Type ?, Clear, Start/Stop and speed controls. |
| `RotatingTriangle` | Rebuilds each animation frame, applies the 3D rotation with `Matrix4` and perspective, and chooses the front or back colour. |
| `TrianglePainter` | `CustomPainter` that places the corners using the law of cosines, scales the triangle to fit, centres it and draws it. |

## How the 3D rotation works

An `AnimationController` produces a value from 0 to 1 every turn and repeats.
Each frame, `RotatingTriangle` turns that value into an angle and builds a
rotation matrix (`rotateY` for the spin, `rotateX` for the tilt). A small
perspective value (`setEntry(3, 2, 0.0015)`) makes the nearer edge look larger.

To decide which face is visible, the app rotates the triangle's surface normal
(0, 0, 1) with the same matrix. Its z component is entry (2, 2) of the matrix:
positive means the front faces the viewer (light blue), negative means the back
faces the viewer (pink).
