import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A transparent, reusable liquid-glass surface.
///
/// The blur is applied to the real content behind the surface. Refraction is
/// limited to the rounded outline ring, so the content in the center stays
/// readable and geometrically unchanged.
class LiquidGlassSurface extends StatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.scheme,
    required this.radius,
    required this.magnification,
    required this.edgeWidth,
    required this.child,
    required this.surfaceKey,
    this.blurSigma = 3.0,
    this.filterKey,
    this.blurKey,
    this.debugLabel = 'glass',
  });

  final ColorScheme scheme;
  final BorderRadius radius;
  final double magnification;
  final double edgeWidth;
  final Widget child;
  final Key surfaceKey;
  final double blurSigma;
  final Key? filterKey;
  final Key? blurKey;
  final String debugLabel;

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  ImageFilter? _shaderFilter;

  @override
  void initState() {
    super.initState();
    _loadShaderProgram();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magnification != widget.magnification ||
        oldWidget.edgeWidth != widget.edgeWidth ||
        oldWidget.radius != widget.radius) {
      _configureShader();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _loadShaderProgram() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;

    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass_refraction.frag',
      );
      if (!mounted) return;
      _program = program;
      _configureShader();
      setState(() {});
    } catch (_) {
      // The matrix rings below remain available on non-Impeller renderers.
    }
  }

  void _configureShader() {
    final program = _program;
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) return;

    _shader?.dispose();
    final shader = program.fragmentShader()
      ..setFloat(2, widget.edgeWidth * (widget.magnification - 1) * 1.35)
      ..setFloat(3, widget.radius.topLeft.x)
      ..setFloat(4, widget.edgeWidth + 3);

    try {
      _shader = shader;
      _shaderFilter = ImageFilter.shader(shader);
    } on UnsupportedError {
      shader.dispose();
      _shader = null;
      _shaderFilter = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final outerRingWidth = math.max(3.5, widget.edgeWidth * 0.56);
        final innerRingWidth = widget.edgeWidth + 3;
        final outerMagnification = 1 + (widget.magnification - 1) * 1.45;
        final innerMagnification = 1 + (widget.magnification - 1) * 0.65;
        final isDark = widget.scheme.brightness == Brightness.dark;
        final topHighlight = widget.scheme.surfaceBright.withValues(
          alpha: isDark ? 0.34 : 0.52,
        );
        final bottomDepth = widget.scheme.shadow.withValues(
          alpha: isDark ? 0.16 : 0.07,
        );
        final rimColor = Color.lerp(
          widget.scheme.surfaceBright,
          widget.scheme.primary,
          0.2,
        )!.withValues(alpha: isDark ? 0.34 : 0.4);
        final contactInset = math.min(
          widget.radius.topLeft.x * 0.55,
          size.width * 0.16,
        );

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned(
              left: contactInset,
              right: contactInset,
              bottom: -1,
              height: 3,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: Key('${widget.debugLabel}-bottom-contact-shadow'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: widget.scheme.shadow.withValues(
                          alpha: isDark ? 0.24 : 0.14,
                        ),
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: widget.radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropFilter(
                    key: widget.blurKey ?? Key('${widget.debugLabel}-blur'),
                    filter: ImageFilter.blur(
                      sigmaX: widget.blurSigma,
                      sigmaY: widget.blurSigma,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  _ContinuousRefractionLayer(
                    shaderFilter: _shaderFilter,
                    outerFilter: _edgeMagnificationFilter(
                      size,
                      outerMagnification,
                    ),
                    innerFilter: _edgeMagnificationFilter(
                      size,
                      innerMagnification,
                    ),
                    radius: widget.radius,
                    outerRingWidth: outerRingWidth,
                    innerRingWidth: innerRingWidth,
                    filterKey: widget.filterKey,
                    debugLabel: widget.debugLabel,
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: math.min(8, size.height * 0.14),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: Key('${widget.debugLabel}-top-highlight'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              topHighlight,
                              topHighlight.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: math.min(7, size.height * 0.12),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              bottomDepth.withValues(alpha: 0),
                              bottomDepth,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    key: widget.surfaceKey,
                    decoration: BoxDecoration(
                      borderRadius: widget.radius,
                      border: Border.all(color: rimColor, width: 0.9),
                    ),
                    child: widget.child,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  ImageFilter _edgeMagnificationFilter(Size size, double scale) {
    final translateX = size.width * (1 - scale) / 2;
    final translateY = size.height * (1 - scale) / 2;
    return ImageFilter.matrix(
      Float64List.fromList(<double>[
        scale,
        0,
        0,
        0,
        0,
        scale,
        0,
        0,
        0,
        0,
        1,
        0,
        translateX,
        translateY,
        0,
        1,
      ]),
      filterQuality: FilterQuality.medium,
    );
  }
}

class _ContinuousRefractionLayer extends StatelessWidget {
  const _ContinuousRefractionLayer({
    required this.shaderFilter,
    required this.outerFilter,
    required this.innerFilter,
    required this.radius,
    required this.outerRingWidth,
    required this.innerRingWidth,
    required this.debugLabel,
    this.filterKey,
  });

  final ImageFilter? shaderFilter;
  final ImageFilter outerFilter;
  final ImageFilter innerFilter;
  final BorderRadius radius;
  final double outerRingWidth;
  final double innerRingWidth;
  final String debugLabel;
  final Key? filterKey;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      key: Key('$debugLabel-continuous-refraction'),
      clipper: _RoundedRectRingClipper(
        radius: radius,
        outerInset: 0,
        innerInset: innerRingWidth,
      ),
      child: shaderFilter == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                _RefractionLayer(
                  filter: outerFilter,
                  radius: radius,
                  outerInset: 0,
                  innerInset: outerRingWidth,
                  layerKey: Key('$debugLabel-outer-refraction-ring'),
                  filterKey: filterKey,
                ),
                _RefractionLayer(
                  filter: innerFilter,
                  radius: radius,
                  outerInset: outerRingWidth,
                  innerInset: innerRingWidth,
                  layerKey: Key('$debugLabel-inner-refraction-ring'),
                ),
              ],
            )
          : BackdropFilter(
              key: filterKey,
              filter: shaderFilter!,
              child: const SizedBox.expand(),
            ),
    );
  }
}

class _RefractionLayer extends StatelessWidget {
  const _RefractionLayer({
    required this.filter,
    required this.radius,
    required this.outerInset,
    required this.innerInset,
    required this.layerKey,
    this.filterKey,
  });

  final ImageFilter filter;
  final BorderRadius radius;
  final double outerInset;
  final double innerInset;
  final Key layerKey;
  final Key? filterKey;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      key: layerKey,
      clipper: _RoundedRectRingClipper(
        radius: radius,
        outerInset: outerInset,
        innerInset: innerInset,
      ),
      child: BackdropFilter(
        key: filterKey,
        filter: filter,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RoundedRectRingClipper extends CustomClipper<Path> {
  const _RoundedRectRingClipper({
    required this.radius,
    required this.outerInset,
    required this.innerInset,
  });

  final BorderRadius radius;
  final double outerInset;
  final double innerInset;

  @override
  Path getClip(Size size) {
    final outerRect = Offset.zero & size;
    final maxInset = math.max(0, math.min(size.width, size.height) / 2 - 0.01);
    final clippedOuterInset = outerInset.clamp(0, maxInset).toDouble();
    final clippedInnerInset = innerInset
        .clamp(clippedOuterInset, maxInset)
        .toDouble();
    final outer = Path()
      ..addRRect(_roundedRectAtInset(outerRect, clippedOuterInset));
    final inner = Path()
      ..addRRect(_roundedRectAtInset(outerRect, clippedInnerInset));
    return Path.combine(PathOperation.difference, outer, inner);
  }

  RRect _roundedRectAtInset(Rect rect, double inset) {
    final insetRect = rect.deflate(inset);
    final cornerRadius = math.max(0.0, radius.topLeft.x - inset);
    return RRect.fromRectAndRadius(insetRect, Radius.circular(cornerRadius));
  }

  @override
  bool shouldReclip(covariant _RoundedRectRingClipper oldClipper) {
    return radius != oldClipper.radius ||
        outerInset != oldClipper.outerInset ||
        innerInset != oldClipper.innerInset;
  }
}
