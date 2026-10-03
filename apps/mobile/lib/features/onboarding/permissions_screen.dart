import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme.dart';
import '../../core/app_flags.dart';
import '../../ui/widgets.dart';
import 'terms_screen.dart' show signupSteps;

/// 권한 요청 래퍼(테스트에서 교체)
abstract class PermissionGateway {
  Future<bool> requestLocation();
  Future<bool> requestNotification();
}

class DevicePermissionGateway implements PermissionGateway {
  @override
  Future<bool> requestLocation() async => (await Permission.locationWhenInUse.request()).isGranted;

  @override
  Future<bool> requestNotification() async => (await Permission.notification.request()).isGranted;
}

final permissionGatewayProvider = Provider<PermissionGateway>((ref) => DevicePermissionGateway());

/// 권한 안내 (SPEC 8): 대략적 위치(포그라운드)와 알림
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final gateway = ref.read(permissionGatewayProvider);
    await gateway.requestLocation();
    await gateway.requestNotification();
    await ref.read(appFlagsProvider.notifier).markPermissionsIntroDone();
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 4,
      totalSteps: signupSteps,
      title: '거의 다 왔어요!',
      subtitle: '염소가 언제 오는지 알려면\n두 가지 권한이 있으면 좋아요.',
      bottom: Column(
        children: [
          ChunkyButton(label: '허용하기', color: Palette.yellow, loading: _busy, onPressed: _allow),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(appFlagsProvider.notifier).markPermissionsIntroDone(),
            child: const Text('나중에 할게요'),
          ),
        ],
      ),
      child: const SingleChildScrollView(
        child: Column(
          children: [
            _PermissionCard(
              icon: Icons.location_on_rounded,
              color: Palette.sky,
              title: '대략적인 위치',
              body: '지금 어느 시에 있는지만 확인해요. 정확한 좌표는 서버로 보내지 않고, 앱을 보고 있을 때만 써요.',
            ),
            SizedBox(height: 14),
            _PermissionCard(
              icon: Icons.notifications_rounded,
              color: Palette.pink,
              title: '알림',
              body: '편지가 도착하거나 염소가 우리 동네에 오면 알려 드려요.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.outline, width: 2.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Palette.outline, width: 2),
            ),
            child: Icon(icon, color: Palette.textBrown),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: Fonts.title,
                    fontFamilyFallback: Fonts.fallback,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
