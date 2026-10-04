import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config.dart';

enum AdShowResult {
  /// 끝까지 봐서 보상 조건을 채움(포인트는 서버 SSV로 들어온다)
  rewarded,

  /// 중간에 닫음
  dismissed,

  /// 광고를 불러오지 못함(재고 없음, 네트워크 등)
  failed,
}

/// 보상형 광고 보여 주기. 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class AdGateway {
  Future<AdShowResult> showRewarded({required String userId, required bool underAge});
}

/// Google Mobile Ads. 보상 지급은 앱이 하지 않고 AdMob이 서버로 SSV 콜백을 보낸다(SPEC 7.1).
class GoogleAdGateway implements AdGateway {
  bool _initialized = false;

  Future<void> _init(bool underAge) async {
    if (!_initialized) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }
    // 만 19세 미만은 청소년 처리, 모두 콘텐츠 등급 상한을 둔다
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: underAge ? MaxAdContentRating.pg : MaxAdContentRating.t,
        ageRestrictedTreatment: underAge
            ? AgeRestrictedTreatment.teen
            : AgeRestrictedTreatment.unspecified,
      ),
    );
  }

  @override
  Future<AdShowResult> showRewarded({required String userId, required bool underAge}) async {
    await _init(underAge);
    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: AppConfig.admobRewardedUnitId,
      request: const AdRequest(nonPersonalizedAds: true),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    final ad = await loaded.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (ad == null) return AdShowResult.failed;
    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId, customData: 'meeil'),
    );
    final done = Completer<AdShowResult>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!done.isCompleted) {
          done.complete(earned ? AdShowResult.rewarded : AdShowResult.dismissed);
        }
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        if (!done.isCompleted) done.complete(AdShowResult.failed);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }
}

final adGatewayProvider = Provider<AdGateway>((ref) => GoogleAdGateway());
