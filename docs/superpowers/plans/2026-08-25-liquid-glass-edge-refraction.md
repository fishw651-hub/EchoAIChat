# Liquid Glass Edge Refraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Android Flutter bottom navigation resemble a floating liquid-glass lens while preserving an undistorted transparent center.

**Architecture:** Keep the existing five-slot navigation and selected-capsule animation. `_LiquidGlassSurface` gains separately clipped outer and inner `BackdropFilter` rings for stronger edge-only magnification, plus theme-derived highlight and environment-shadow overlays; the content stack remains above those layers.

**Tech Stack:** Flutter Material 3, Dart, `BackdropFilter`, `ImageFilter.matrix`, widget tests.

## Global Constraints

- Only modify the Flutter mobile bottom navigation and its tests.
- Keep the refraction mask to the outline rings; the central region must remain unfiltered.
- Do not add a full-surface color fill, hard-coded `Colors.white`/`Colors.black`, or `withOpacity`.
- Derive highlights and shadows from `ColorScheme` with `withValues(alpha: ...)`.
- Do not alter page mapping, tab behavior, desktop navigation, Web, or server code.

---

### Task 1: Prove and Implement Edge-Only Glass Depth

**Files:**
- Modify: `test/liquid_glass_bottom_nav_bar_test.dart`
- Modify: `lib/screens/liquid_glass_bottom_nav_bar.dart`

**Interfaces:**
- Consumes: `LiquidGlassBottomNavBar` public constructor and its existing `BackdropFilter` structure.
- Produces: two refraction rings per glass surface, with keyed top highlight and bottom environment shadow overlays.

- [ ] **Step 1: Write failing widget assertions**

```dart
expect(find.byKey(const Key('glass-outer-refraction-ring')), findsNWidgets(2));
expect(find.byKey(const Key('glass-inner-refraction-ring')), findsNWidgets(2));
expect(find.byKey(const Key('glass-top-highlight')), findsNWidgets(2));
expect(find.byKey(const Key('glass-bottom-environment-shadow')), findsNWidgets(2));
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter --suppress-analytics test test\\liquid_glass_bottom_nav_bar_test.dart`

Expected: FAIL because the new keyed layered glass elements do not exist.

- [ ] **Step 3: Add layered ring and lighting widgets**

```dart
_RefractionLayer(
  filter: _edgeMagnificationFilter(size, outerMagnification),
  radius: radius,
  edgeWidth: outerEdgeWidth,
  layerKey: const Key('glass-outer-refraction-ring'),
),
_RefractionLayer(
  filter: _edgeMagnificationFilter(size, innerMagnification),
  radius: radius,
  edgeWidth: innerEdgeWidth,
  layerKey: const Key('glass-inner-refraction-ring'),
),
```

Place both refraction layers behind the tab child, then paint a top-only highlight and bottom-only environment shadow above the refraction layers without a full-surface fill.

- [ ] **Step 4: Run the focused test and verify it passes**

Run: `flutter --suppress-analytics test test\\liquid_glass_bottom_nav_bar_test.dart`

Expected: PASS with all liquid-glass widget tests green.

### Task 2: Verify the Android Deliverable

**Files:**
- Verify: `lib/screens/liquid_glass_bottom_nav_bar.dart`
- Verify: `test/liquid_glass_bottom_nav_bar_test.dart`

**Interfaces:**
- Consumes: completed edge-only glass surface.
- Produces: analyzed, regression-tested Android release APK.

- [ ] **Step 1: Format and perform targeted analysis**

Run: `dart format lib\\screens\\liquid_glass_bottom_nav_bar.dart test\\liquid_glass_bottom_nav_bar_test.dart`

Run: `dart --suppress-analytics analyze lib\\screens\\liquid_glass_bottom_nav_bar.dart lib\\screens\\home_screen.dart test\\liquid_glass_bottom_nav_bar_test.dart test\\home_create_action_test.dart`

Expected: formatter exits 0 and analyzer reports no issues.

- [ ] **Step 2: Run navigation regression tests**

Run: `flutter --suppress-analytics test test\\liquid_glass_bottom_nav_bar_test.dart test\\home_create_action_test.dart test\\home_page_mapping_test.dart test\\ui_cleanup_regression_test.dart`

Expected: all listed tests pass.

- [ ] **Step 3: Build Android release APK**

Run: `flutter --suppress-analytics build apk --release`

Expected: `build\\app\\outputs\\flutter-apk\\app-release.apk` is generated after the code changes.
