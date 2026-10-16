import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/services/notification_service.dart';

/// These cover the one part of NotificationService that is pure logic and
/// also the part most likely to rot: the payload a notification carries,
/// and the route a tap on it resolves to.
///
/// The failure this guards against is silent. A payload that no longer
/// maps anywhere makes a tap do nothing at all; a route name that drifts
/// from main.dart's `routes` table makes it throw inside Navigator. Neither
/// shows up in analysis, and neither is visible until a user taps a
/// notification in production.
void main() {
  group('routeForPayload', () {
    test('maps each payload to its route', () {
      expect(
        NotificationService.routeForPayload(
            NotificationService.payloadHoroscope),
        NotificationService.routeHoroscope,
      );
      expect(
        NotificationService.routeForPayload(NotificationService.payloadChat),
        NotificationService.routeChat,
      );
      expect(
        NotificationService.routeForPayload(NotificationService.payloadMulank),
        NotificationService.routeMulank,
      );
    });

    test('returns null for an unknown payload', () {
      // A notification posted by an older build, still sitting in the
      // shade across an app upgrade, can carry anything — or nothing.
      expect(NotificationService.routeForPayload(null), isNull);
      expect(NotificationService.routeForPayload(''), isNull);
      expect(NotificationService.routeForPayload('kundli'), isNull);
    });

    test('route names are absolute and distinct', () {
      final routes = {
        NotificationService.routeHoroscope,
        NotificationService.routeChat,
        NotificationService.routeMulank,
      };
      expect(routes, hasLength(3), reason: 'two routes collided');
      for (final r in routes) {
        expect(r, startsWith('/'),
            reason: 'MaterialApp.routes keys must be absolute paths');
      }
    });

    test('no route is the initial route', () {
      // MaterialApp asserts if `routes` contains '/' while `home` is also
      // set, which it is (AnimatedSplashScreen). Catching that here beats
      // catching it as a red screen on launch.
      expect(
        {
          NotificationService.routeHoroscope,
          NotificationService.routeChat,
          NotificationService.routeMulank,
        },
        isNot(contains('/')),
      );
    });
  });
}
