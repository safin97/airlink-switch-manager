import 'dart:convert';

import 'package:airlink_manager/network_config.dart';
import 'package:airlink_manager/network_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

NetworkConfig staticDraft({
  String address = '192.168.88.2',
  String prefix = '24',
  String gateway = '192.168.88.1',
  String dns = '1.1.1.1, 192.168.88.1',
}) => NetworkConfig.validate(
  mode: 'static',
  interfaceName: 'bridge-mgmt',
  address: address,
  prefix: prefix,
  gateway: gateway,
  dns: dns,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('static draft roundtrips and DHCP excludes hidden static values', () {
    final value = staticDraft();
    expect(NetworkConfig.fromJson(value.toJson()).toJson(), value.toJson());
    final dhcp = NetworkConfig.validate(
      mode: 'dhcp',
      interfaceName: 'bridge-mgmt',
      address: 'invalid hidden value',
      gateway: 'invalid',
      dns: 'invalid',
    );
    expect(dhcp.toJson().keys, isNot(contains('address')));
    expect(dhcp.toJson().keys, isNot(contains('dns')));
    expect(staticDraft(gateway: '', dns: '').dns, isEmpty);
    expect(
      staticDraft(address: '200.1.1.2', gateway: '200.1.1.1').address,
      '200.1.1.2',
    );
  });

  test('rejects malformed, non-unicast, network and broadcast addresses', () {
    for (final value in [
      '0.0.0.0',
      '127.0.0.1',
      '224.1.1.1',
      '255.255.255.255',
      '192.168.88.0',
      '192.168.88.255',
      '192.168.088.2',
      '192.168.1.256',
      '192.168.1',
      '1e2.0.0.1',
      '::1',
      '192.168.1.2/24',
    ]) {
      expect(() => staticDraft(address: value), throwsFormatException);
    }
    for (final value in ['0', '31', '32', '24.0', '-1', '']) {
      expect(() => staticDraft(prefix: value), throwsFormatException);
    }
  });

  test(
    'checks gateway subnet and DNS entries without assuming reachability',
    () {
      for (final value in [
        '192.168.89.1',
        '192.168.88.0',
        '192.168.88.255',
        '192.168.88.2',
      ]) {
        expect(() => staticDraft(gateway: value), throwsFormatException);
      }
      for (final value in [
        '1.1.1.1,',
        '1.1.1.1,1.1.1.1',
        'abc',
        '127.0.0.1',
        '1.1.1.1,8.8.8.8,9.9.9.9,4.4.4.4',
      ]) {
        expect(() => staticDraft(dns: value), throwsFormatException);
      }
      expect(
        () => NetworkConfig.validate(mode: 'dhcp', interfaceName: ''),
        throwsFormatException,
      );
      expect(
        () => NetworkConfig.fromJson({'schema': 'unknown'}),
        throwsFormatException,
      );
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('network draft saves, restores and stays isolated at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget screen(String id) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NetworkSettings(key: ValueKey(id), draftId: id, demo: true),
          ),
        ),
      );
      await tester.pumpWidget(screen('demo-one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Static IPv4'));
      await tester.pumpAndSettle();
      for (final entry in {
        'interface': 'bridge-mgmt',
        'address': '192.168.88.2',
        'prefix': '24',
        'gateway': '192.168.88.1',
        'dns': '1.1.1.1',
      }.entries) {
        await tester.enterText(
          find.byKey(Key('network-${entry.key}')),
          entry.value,
        );
      }
      await tester.ensureVisible(find.byKey(const Key('network-save')));
      await tester.tap(find.byKey(const Key('network-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Saved on this computer/browser'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('network-apply')))
            .onPressed,
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('airlink.network-draft.v1.demo-one')!,
        )['mode'],
        'static',
      );
      await tester.pumpWidget(screen('demo-two'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('network-address')), findsNothing);
      expect(
        find.textContaining('Saved on this computer/browser'),
        findsNothing,
      );
      await tester.pumpWidget(screen('demo-one'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('network-address')))
            .controller!
            .text,
        '192.168.88.2',
      );
      await tester.enterText(
        find.byKey(const Key('network-address')),
        '192.168.88.255',
      );
      await tester.ensureVisible(find.byKey(const Key('network-save')));
      await tester.tap(find.byKey(const Key('network-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('cannot be the subnet network'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Saved on this computer/browser'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('corrupt stored draft displays a recoverable error', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'airlink.network-draft.v1.bad': '{',
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NetworkSettings(draftId: 'bad', demo: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Saved draft could not be loaded'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('network-apply')))
          .onPressed,
      isNull,
    );
  });
}
