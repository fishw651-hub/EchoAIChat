import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/l10n/app_localizations.dart';

void main() {
  test('account flow localization keys exist in Chinese', () {
    final keys = <String>[
      'availableBalance',
      'subscriptionDailyQuota',
      'todayQuota',
      'todayUsed',
      'syncConfirmContent',
      'forgotPasswordTitle',
      'resetPasswordDesc',
      'registeredEmail',
      'registeredEmailHelper',
      'verificationCode',
      'send',
      'newPassword',
      'confirmNewPassword',
      'passwordMinSixHint',
      'validEmailRequired',
      'verificationCodeSentEmail',
      'enterTwelveDigitCode',
      'passwordTooShortSix',
      'passwordResetSuccess',
      'notLoggedIn',
      'deviceSettingFailed',
      'deleteDevice',
      'deleteDeviceConfirm',
      'deviceDeleteFailed',
      'editDeviceName',
      'deviceNameHint',
      'deviceUpdateFailed',
      'realTimeSyncTitle',
      'realTimeSyncDesc',
      'loggedInDevicesCount',
      'unnamedDevice',
      'currentDevice',
      'masterDevice',
      'slaveDevice',
      'setAsMaster',
      'setAsSlave',
      'editName',
      'feedbackContentMinLength',
      'feedbackContactRequired',
      'feedbackSubmitted',
      'feedbackCategory',
      'feedbackContent',
      'feedbackContentHint',
      'feedbackContact',
      'feedbackContactHint',
      'submitting',
      'submit',
      'feedbackCategoryFeature',
      'feedbackCategoryFeatureTweak',
      'feedbackCategoryBug',
      'feedbackCategoryUi',
      'feedbackCategoryPricing',
      'feedbackCategoryOther',
      'feedbackLoginRequired',
      'feedbackSubmitFailed',
      'feedbackNetworkErrorWithDetail',
    ];

    for (final locale in const [Locale('zh')]) {
      final l10n = AppLocalizations(locale);
      for (final key in keys) {
        expect(
          l10n.get(key),
          isNot(key),
          reason: '${locale.languageCode}: $key',
        );
      }
    }
  });

  test('account flow parameterized localization keys replace placeholders', () {
    final l10n = AppLocalizations(const Locale('zh'));

    expect(l10n.getP('loggedInDevicesCount', {'count': '2'}), contains('2'));
    expect(
      l10n.getP('deviceSettingFailed', {'error': 'boom'}),
      contains('boom'),
    );
    expect(
      l10n.getP('feedbackNetworkErrorWithDetail', {'error': 'timeout'}),
      contains('timeout'),
    );
  });
}
