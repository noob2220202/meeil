import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../goats/schedule.dart';
import 'goat_scene.dart';
import 'map_geometry.dart';
import 'map_painters.dart';

/// 지도를 바깥에서 움직이는 손잡이(내 위치로, 전국 보기)
class MapViewController {
  _MapViewState? _state;

  void showAll() => _state?._animateTo(_state!._fitMatrix());
  void focusRegion(String code, {double relZoom = 5.0}) => _state?._focus(code, relZoom);
}

/// 일러스트 지도 + 염소. 땅은 확대/이동되고, 염소·이름표는 화면 크기를 유지한다.
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.geo,
    required this.schedule,
    this.myRegion,
    this.selectedRegion,
    this.selectedGoat,
    this.controller,
    this.onRegionTap,
    this.onGoatTap,
    this.clock,
  });

  final MapGeometry geo;
  final GoatSchedule? schedule;
  final String? myRegion;
  final String? selectedRegion;
  final String? selectedGoat;
  final MapViewController? controller;
  final ValueChanged<String?>? onRegionTap;
  final ValueChanged<GoatRef>? onGoatTap;

  /// 테스트·스크린샷용 고정 시각
  final DateTime Function()? clock;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  final _tc = TransformationController();
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _elapsed = Duration.zero;
  Size _viewport = Size.zero;
  double _fitZoom = 1;
  AnimationController? _anim;

  /// "애니메이션 줄이기"일 때: 걷는 동작 없이 1초마다 위치만 갱신
  Timer? _slowTimer;

  double get _t => _elapsed.inMicroseconds / 1e6;
  double get _zoom => _tc.value.getMaxScaleOnAxis();
  double get _relZoom => _zoom / _fitZoom;

  /// 전국 보기에선 작게(수도권에 몰려도 한 마리씩 보이게), 확대할수록 크게
  double get _goatSize => (32 * math.pow(_relZoom, 0.3)).clamp(32.0, 60.0).toDouble();

  DateTime _now() => widget.clock?.call() ?? widget.schedule?.serverNow() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _ticker = createTicker((elapsed) {
      _elapsed = elapsed;
      _frame.value++;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      if (_ticker.isActive) _ticker.stop();
      _slowTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _frame.value++);
    } else {
      _slowTimer?.cancel();
      _slowTimer = null;
      if (!_ticker.isActive) _ticker.start();
    }
  }

  @override
  void didUpdateWidget(MapView old) {
    super.didUpdateWidget(old);
    widget.controller?._state = this;
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _ticker.dispose();
    _anim?.dispose();
    _tc.dispose();
    _frame.dispose();
    super.dispose();
  }

  Matrix4 _fitMatrix() {
    final b = widget.geo.bounds;
    final s = math.min(_viewport.width / b.width, _viewport.height / b.height) * 0.96;
    final dx = (_viewport.width - b.width * s) / 2;
    final dy = (_viewport.height - b.height * s) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _focus(String code, double relZoom) {
    final shape = widget.geo.regions[code];
    if (shape == null) return;
    final s = _fitZoom * relZoom;
    final local = shape.center - widget.geo.bounds.topLeft;
    final m = Matrix4.identity()
      ..translateByDouble(
        _viewport.width / 2 - local.dx * s,
        _viewport.height * 0.55 - local.dy * s,
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);
    _animateTo(m);
  }

  void _animateTo(Matrix4 target) {
    _anim?.dispose();
    final begin = _tc.value.clone();
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    final curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    final tween = Matrix4Tween(begin: begin, end: target);
    c.addListener(() => _tc.value = tween.evaluate(curve));
    _anim = c..forward();
  }

  Rect _visibleWorld() {
    final inv = Matrix4.inverted(_tc.value);
    final tl = MatrixUtils.transformPoint(inv, Offset.zero);
    final br = MatrixUtils.transformPoint(inv, Offset(_viewport.width, _viewport.height));
    return Rect.fromPoints(tl, br).shift(widget.geo.bounds.topLeft);
  }

  List<GoatSprite> _sprites() => buildGoatSprites(
    geo: widget.geo,
    schedule: widget.schedule,
    now: _now(),
    t: _t,
    relZoom: _relZoom,
    visibleWorld: _visibleWorld(),
    goatSize: _goatSize,
  );

  Offset _toScreen(Offset world) =>
      MatrixUtils.transformPoint(_tc.value, world - widget.geo.bounds.topLeft);

  void _onTap(Offset screen) {
    // 1) 염소(앞에 그려진 것부터)
    final size = _goatSize;
    final sprites = _sprites()..sort((a, b) => b.priority.compareTo(a.priority));
    for (final s in sprites) {
      final body = _toScreen(s.world) + s.screenNudge - Offset(0, size * 0.45);
      if ((body - screen).distance <= size * 0.55) {
        final ref = goatRefOf(s.id);
        if (ref != null) widget.onGoatTap?.call(ref);
        return;
      }
    }
    // 2) 지역
    final world =
        MatrixUtils.transformPoint(Matrix4.inverted(_tc.value), screen) + widget.geo.bounds.topLeft;
    widget.onRegionTap?.call(widget.geo.hitTest(world));
  }

  @override
  Widget build(BuildContext context) {
    final geo = widget.geo;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (size != _viewport) {
          final first = _viewport == Size.zero;
          _viewport = size;
          final fit = _fitMatrix();
          _fitZoom = fit.getMaxScaleOnAxis();
          if (first) _tc.value = fit;
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTap(d.localPosition),
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: seaColor)),
              InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                minScale: _fitZoom * 0.8,
                maxScale: _fitZoom * 14,
                boundaryMargin: EdgeInsets.all(math.max(size.width, size.height) * 0.6),
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _tc,
                  builder: (context, m, _) => RepaintBoundary(
                    child: CustomPaint(
                      size: geo.bounds.size,
                      isComplex: true,
                      painter: LandPainter(
                        geo: geo,
                        zoom: m.getMaxScaleOnAxis(),
                        myRegion: widget.myRegion,
                        selectedRegion: widget.selectedRegion,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: OverlayPainter(
                        repaint: Listenable.merge([_frame, _tc]),
                        geo: geo,
                        matrixOf: () => _tc.value,
                        fitZoom: _fitZoom,
                        time: () => _t,
                        sprites: _sprites,
                        myRegion: widget.myRegion,
                        goatSizeOf: () => _goatSize,
                        highlightGoat: widget.selectedGoat,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
