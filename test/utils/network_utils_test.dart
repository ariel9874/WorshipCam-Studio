import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:camo_clone/utils/network_utils.dart';

class MockNetworkInterface implements NetworkInterface {
  @override
  final String name;
  @override
  final List<InternetAddress> addresses;

  MockNetworkInterface(this.name, this.addresses);

  @override
  int get index => 0;
}

void main() {
  group('NetworkUtils', () {
    test('findBestIp elige rndis0 (USB Tethering) por sobre wlan0 (Wi-Fi)', () {
      final interfaces = [
        MockNetworkInterface('wlan0', [InternetAddress('192.168.1.100', type: InternetAddressType.IPv4)]),
        MockNetworkInterface('rndis0', [InternetAddress('192.168.42.129', type: InternetAddressType.IPv4)]),
      ];

      final bestIp = NetworkUtils.findBestIp(interfaces);
      expect(bestIp, '192.168.42.129');
    });

    test('findBestIp elige ap0 (Hotspot) si no hay rndis0', () {
      final interfaces = [
        MockNetworkInterface('wlan0', [InternetAddress('192.168.1.100', type: InternetAddressType.IPv4)]),
        MockNetworkInterface('ap0', [InternetAddress('192.168.43.1', type: InternetAddressType.IPv4)]),
      ];

      final bestIp = NetworkUtils.findBestIp(interfaces);
      expect(bestIp, '192.168.43.1');
    });

    test('findBestIp ignora rmnet (Datos móviles) si hay otra interfaz local', () {
      final interfaces = [
        MockNetworkInterface('rmnet0', [InternetAddress('10.0.0.5', type: InternetAddressType.IPv4)]),
        MockNetworkInterface('wlan0', [InternetAddress('192.168.1.100', type: InternetAddressType.IPv4)]),
      ];

      final bestIp = NetworkUtils.findBestIp(interfaces);
      expect(bestIp, '192.168.1.100');
    });

    test('findBestIp ignora direcciones IPv6 y loopback', () {
      final interfaces = [
        MockNetworkInterface('wlan0', [
          InternetAddress('::1', type: InternetAddressType.IPv6), // IPv6
          InternetAddress('127.0.0.1', type: InternetAddressType.IPv4), // Loopback
          InternetAddress('192.168.1.50', type: InternetAddressType.IPv4), // Válida
        ]),
      ];

      final bestIp = NetworkUtils.findBestIp(interfaces);
      expect(bestIp, '192.168.1.50');
    });
  });
}
