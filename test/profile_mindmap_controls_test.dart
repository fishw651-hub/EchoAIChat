import 'package:aichat/theme/app_theme.dart';
import 'package:aichat/widgets/profile_mindmap_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile mind map starts at a readable scale', () {
    expect(ProfileMindMapViewport.initialScale(const Size(390, 700)), 0.55);
    expect(ProfileMindMapViewport.initialScale(const Size(1200, 900)), 1.0);
  });

  test('profile source labels distinguish manual and AI observations', () {
    expect(profileSourceLabel('manual'), '手动记录');
    expect(profileSourceLabel('ai_extracted'), 'AI 观察');
    expect(profileSourceLabel('category_supplement'), '问卷补充');
  });

  testWidgets('mind map controls expose zoom and reset actions', (
    tester,
  ) async {
    var zoomIn = 0;
    var zoomOut = 0;
    var reset = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oceanLight(),
        home: Scaffold(
          body: ProfileMindMapControls(
            onZoomIn: () => zoomIn++,
            onZoomOut: () => zoomOut++,
            onReset: () => reset++,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('放大画像'));
    await tester.tap(find.byTooltip('缩小画像'));
    await tester.tap(find.byTooltip('复位画像'));

    expect(zoomIn, 1);
    expect(zoomOut, 1);
    expect(reset, 1);
  });
}
