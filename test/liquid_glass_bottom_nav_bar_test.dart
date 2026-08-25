import 'package:aichat/screens/liquid_glass_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({int currentIndex = 0, bool disableAnimations = false}) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF557C95));
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: LiquidGlassBottomNavBar(
            scheme: scheme,
            currentIndex: currentIndex,
            tabBuilder: (index, selected) => Text(
              'tab-$index-${selected ? 'selected' : 'idle'}',
              key: ValueKey('tab-$index'),
            ),
            centerAction: const Icon(
              key: Key('center-action'),
              Icons.add_rounded,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'renders a five-slot glass bar without a round create container',
    (tester) async {
      await tester.pumpWidget(buildSubject());

      final navigationBar = find.byType(LiquidGlassBottomNavBar);
      expect(
        find.descendant(
          of: navigationBar,
          matching: find.byType(BackdropFilter),
        ),
        findsNWidgets(6),
      );
      expect(
        find.descendant(
          of: navigationBar,
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navigationBar, matching: find.byType(CustomPaint)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: navigationBar,
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('selected-glass-capsule')), findsOneWidget);
      expect(find.byKey(const Key('center-create-slot')), findsOneWidget);
      expect(
        find.byKey(const Key('glass-refraction-fallback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('glass-outer-refraction-ring')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const Key('glass-inner-refraction-ring')),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<BackdropFilter>(
              find.byKey(const Key('glass-refraction-fallback')),
            )
            .filter
            .toString(),
        startsWith('ImageFilter.matrix('),
      );
      expect(
        find.descendant(of: navigationBar, matching: find.byType(ClipOval)),
        findsNothing,
      );
    },
  );

  testWidgets('keeps the center create slot aligned with tab content', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    final centerSlot = tester.getRect(
      find.byKey(const Key('center-create-slot')),
    );
    final firstTab = tester.getRect(find.byKey(const Key('tab-0')));

    expect(centerSlot.center.dy, closeTo(firstTab.center.dy, 8));
    expect(tester.getRect(find.byKey(const Key('center-action'))).height, 32);
  });

  testWidgets('keeps the glass surfaces clear of dark fills and shadows', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(currentIndex: 3));

    for (final key in const <Key>[
      Key('glass-clear-main-surface'),
      Key('glass-clear-selection-surface'),
    ]) {
      final surface = tester.widget<DecoratedBox>(find.byKey(key));
      final decoration = surface.decoration as BoxDecoration;

      expect(decoration.color, isNull);
      expect(decoration.boxShadow, isNull);
    }
  });

  testWidgets('adds a transparent Gaussian blur behind the glass layers', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    final blur = tester.widget<BackdropFilter>(
      find.byKey(const Key('glass-main-blur')),
    );
    expect(blur.filter.toString(), startsWith('ImageFilter.blur('));
  });

  testWidgets('layers edge-only refraction with floating glass lighting', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(currentIndex: 1));

    expect(
      find.byKey(const Key('glass-outer-refraction-ring')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const Key('glass-inner-refraction-ring')),
      findsNWidgets(2),
    );
    expect(find.byKey(const Key('glass-top-highlight')), findsNWidgets(2));
    expect(
      find.byKey(const Key('glass-bottom-contact-shadow')),
      findsNWidgets(2),
    );

    final outerRing = tester.widget<ClipPath>(
      find.byKey(const Key('glass-outer-refraction-ring')).first,
    );
    final innerRing = tester.widget<ClipPath>(
      find.byKey(const Key('glass-inner-refraction-ring')).first,
    );

    expect(outerRing.clipper, isNot(same(innerRing.clipper)));
  });

  testWidgets('keeps glass depth in a narrow bottom contact shadow', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(currentIndex: 1));

    expect(
      find.byKey(const Key('glass-continuous-refraction')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const Key('glass-bottom-environment-shadow')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('glass-bottom-contact-shadow')),
      findsNWidgets(2),
    );

    final contactShadow = find.byKey(const Key('glass-bottom-contact-shadow'));
    final mainSurface = find.byKey(const Key('glass-clear-main-surface'));

    expect(tester.getRect(contactShadow.first).height, lessThanOrEqualTo(4));
    expect(
      tester.getRect(contactShadow.first).top,
      greaterThan(tester.getRect(mainSurface).bottom - 4),
    );
  });

  testWidgets('renders four tabs and the center action', (tester) async {
    await tester.pumpWidget(buildSubject(currentIndex: 2));

    expect(find.byKey(const Key('tab-0')), findsOneWidget);
    expect(find.byKey(const Key('tab-1')), findsOneWidget);
    expect(find.byKey(const Key('tab-2')), findsOneWidget);
    expect(find.byKey(const Key('tab-3')), findsOneWidget);
    expect(find.byKey(const Key('center-action')), findsOneWidget);
    expect(find.text('tab-2-selected'), findsOneWidget);
  });

  testWidgets('moves the selected capsule without changing bar layout', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(currentIndex: 0));
    final capsule = tester.getRect(
      find.byKey(const Key('selected-glass-capsule')),
    );
    final bar = tester.getRect(find.byType(LiquidGlassBottomNavBar));

    await tester.pumpWidget(buildSubject(currentIndex: 2));
    await tester.pump(const Duration(milliseconds: 120));

    final moved = tester.getRect(
      find.byKey(const Key('selected-glass-capsule')),
    );
    expect(moved.center.dx, greaterThan(capsule.center.dx));
    expect(moved.height, closeTo(capsule.height, 0.5));
    expect(
      tester.getRect(find.byType(LiquidGlassBottomNavBar)).height,
      bar.height,
    );
  });

  testWidgets('disables capsule stretch when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(currentIndex: 0, disableAnimations: true),
    );
    await tester.pumpWidget(
      buildSubject(currentIndex: 2, disableAnimations: true),
    );
    await tester.pump();

    final capsule = tester.getRect(
      find.byKey(const Key('selected-glass-capsule')),
    );
    expect(capsule.width, greaterThan(40));
    expect(capsule.height, lessThan(64));
  });

  testWidgets('keeps the layered glass layout stable on a narrow dark screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF557C95),
      brightness: Brightness.dark,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: LiquidGlassBottomNavBar(
            scheme: scheme,
            currentIndex: 1,
            tabBuilder: (index, selected) => Text(
              'tab-$index-${selected ? 'selected' : 'idle'}',
              key: ValueKey('narrow-tab-$index'),
            ),
            centerAction: const Icon(
              key: Key('narrow-center-action'),
              Icons.add_rounded,
              size: 32,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('selected-glass-capsule')), findsOneWidget);
    expect(find.byKey(const Key('center-create-slot')), findsOneWidget);
    expect(find.text('tab-1-selected'), findsOneWidget);
  });

  testWidgets('latest tab selection wins during rapid switching', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(currentIndex: 0));
    await tester.pumpWidget(buildSubject(currentIndex: 1));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(buildSubject(currentIndex: 3));
    await tester.pumpAndSettle();

    expect(find.text('tab-3-selected'), findsOneWidget);
    final capsule = tester.getRect(
      find.byKey(const Key('selected-glass-capsule')),
    );
    expect(capsule.center.dx, greaterThan(500));
  });
}
