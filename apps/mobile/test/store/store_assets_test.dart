@Tags(['store-assets'])
library;

// 앱 아이콘(어댑티브), 스플래시 그림, 스토어 그래픽(아이콘 512, 피처 그래픽 1024×500, 스크린샷 8장)을
// 앱과 같은 SVG·염소 그리기 코드로 렌더링한다(SPEC 12.3). 외부 이미지 생성 없음.
//   cd apps/mobile && flutter test --tags screenshot && flutter test --tags store-assets
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/ui/widgets.dart';

import '../screenshots/screenshot_helper.dart';

const res = 'android/app/src/main/res';
const store = '../../docs/store';

/// [child]를 논리 크기 [w]×[h]로 그려 px 크기 [pw]×[ph] PNG로 저장
Future<void> render(
  WidgetTester tester,
  Widget child,
  String path, {
  required double w,
  required double h,
  required int pw,
}) async {
  tester.view.physicalSize = const Size(2400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: w,
            height: h,
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: pw / w);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// 아이콘 그림: 노랑 바탕 위 우체부 염소 얼굴. [bg]가 없으면 투명(어댑티브 전경)
class IconArt extends StatelessWidget {
  const IconArt({super.key, this.bg = Palette.yellow, this.faceScale = 0.78, this.round = false});
  final Color? bg;
  final double faceScale;
  final bool round;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final s = box.biggest.shortestSide;
      return Container(
        decoration: bg == null
            ? null
            : BoxDecoration(
                color: bg,
                shape: round ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: round ? null : BorderRadius.circular(s * 0.22),
              ),
        alignment: const Alignment(0, 0.08),
        child: IllustrationImage(Illustration.goat, size: s * faceScale),
      );
    },
  );
}

const _shots = <(String, String, String, Color)>[
  ('m2_01_map_nation', '우체부 염소들이 전국을 돌아요', '지도 위를 뒤뚱뒤뚱 걷는 염소를 만나요', Palette.sky),
  ('m3_01_compose_ready', '우리 동네에 염소가 오면', '편지를 맡길 수 있어요', Palette.yellow),
  ('m3_03_handoff', '염소 가방에 편지를 쏙', '도착까지 최대 3일, 느려서 더 설레요', Palette.mint),
  ('m3_08_arrival', '편지가 도착했어요!', '염소가 문 앞까지 가져다줘요', Palette.pink),
  ('m3_04_inbox', '내 편지함', '받은 편지·보낸 편지·휴지통', Palette.sky),
  ('m4_02_nation_paper', '전국·도·시 롤링페이퍼', '두루마리 염소가 오면 한마디', Palette.mint),
  ('m5_03_attendance_calendar', '출석하고 업적 모으기', '포인트·칭호·편지지 선물', Palette.yellow),
  ('m6_03_report_sheet', '신고·차단으로 안전하게', '나쁜 편지는 염소가 냠냠', Palette.pink),
];

void main() {
  testWidgets('앱 아이콘·스플래시·스토어 그래픽', (tester) async {
    await tester.runAsync(loadAppFonts);

    // 1) 레거시 아이콘(Android 7 이하) + 어댑티브 전경(108dp 중 가운데 66dp 안전 영역)
    const dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    for (final MapEntry(key: d, value: k) in dens.entries) {
      await render(
        tester,
        const IconArt(),
        '$res/mipmap-$d/ic_launcher.png',
        w: 192,
        h: 192,
        pw: (48 * k).round(),
      );
      await render(
        tester,
        const IconArt(round: true),
        '$res/mipmap-$d/ic_launcher_round.png',
        w: 192,
        h: 192,
        pw: (48 * k).round(),
      );
      await render(
        tester,
        const IconArt(bg: null, faceScale: 0.56),
        '$res/mipmap-$d/ic_launcher_foreground.png',
        w: 216,
        h: 216,
        pw: (108 * k).round(),
      );
    }
    // 2) 스플래시 가운데 그림(투명 배경 얼굴)
    await render(
      tester,
      const IconArt(bg: null, faceScale: 1),
      '$res/drawable-nodpi/splash_goat.png',
      w: 288,
      h: 288,
      pw: 288,
    );

    // 3) 스토어 아이콘 512
    await render(tester, const IconArt(), '$store/icon-512.png', w: 512, h: 512, pw: 512);

    // 4) 피처 그래픽 1024×500
    await render(
      tester,
      const _FeatureGraphic(),
      '$store/feature-graphic.png',
      w: 1024,
      h: 500,
      pw: 1024,
    );

    // 5) 스크린샷 8장(1080×1920, 위에 문구)
    for (final (i, (file, title, sub, color)) in _shots.indexed) {
      final src = File('build/screenshots/$file.png');
      if (!src.existsSync()) fail('먼저 flutter test --tags screenshot 으로 $file.png를 만들어 주세요');
      final image = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(src.readAsBytesSync());
        return (await codec.getNextFrame()).image;
      });
      await render(
        tester,
        _StoreShot(image: image!, title: title, sub: sub, color: color),
        '$store/screenshots/${(i + 1).toString().padLeft(2, '0')}_$file.png',
        w: 540,
        h: 960,
        pw: 1080,
      );
    }
  });
}

class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic();

  @override
  Widget build(BuildContext context) => Container(
    color: Palette.cream,
    child: Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _HillsPainter())),
        Positioned(
          left: 70,
          top: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '메에일',
                style: TextStyle(
                  fontFamily: Fonts.title,
                  fontSize: 120,
                  color: Palette.textBrown,
                  height: 1,
                ),
              ),
              SizedBox(height: 18),
              Text(
                '우체부 염소가 전해 주는 느린 편지',
                style: TextStyle(fontFamily: Fonts.body, fontSize: 34, color: Palette.textBrown),
              ),
            ],
          ),
        ),
        const Positioned(
          right: 70,
          top: 50,
          child: SizedBox(width: 300, height: 300, child: IconArt(bg: null, faceScale: 1)),
        ),
      ],
    ),
  );
}

/// 아래쪽 언덕과 걸어가는 염소 셋
class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.86)
        ..quadraticBezierTo(size.width * 0.3, h * 0.74, size.width * 0.6, h * 0.84)
        ..quadraticBezierTo(size.width * 0.85, h * 0.92, size.width, h * 0.8)
        ..lineTo(size.width, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = Palette.mint,
    );
    const looks = [
      GoatLook(hat: Color(0xFFE8505B), bag: Color(0xFFF6C177)),
      RollingLooks.nation,
      GoatLook(hat: Color(0xFF3F8EFC), bag: Color(0xFFFFC9D6)),
    ];
    for (final (i, look) in looks.indexed) {
      GoatPainterKit.paint(
        canvas,
        at: Offset(size.width * (0.42 + i * 0.12), h * (0.86 - (i == 1 ? 0.04 : 0))),
        size: 86,
        look: look,
        t: 0.13 + i * 0.21,
      );
    }
  }

  @override
  bool shouldRepaint(_HillsPainter old) => false;
}

class _StoreShot extends StatelessWidget {
  const _StoreShot({
    required this.image,
    required this.title,
    required this.sub,
    required this.color,
  });
  final ui.Image image;
  final String title;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    color: color,
    padding: const EdgeInsets.fromLTRB(28, 44, 28, 0),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: Fonts.title, fontSize: 34, color: Palette.textBrown),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: Fonts.body, fontSize: 18, color: Palette.textBrown),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(color: Palette.outline, width: 4),
              boxShadow: const [
                BoxShadow(color: Color(0x335A4636), blurRadius: 12, offset: Offset(0, 6)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: RawImage(image: image, fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
        ),
      ],
    ),
  );
}
