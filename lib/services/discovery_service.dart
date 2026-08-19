import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

class DiscoveryService {
  static Future<String?> discoverDevice({Duration timeout = const Duration(seconds: 5)}) async {
    final completer = Completer<String?>();
    Discovery? discovery;

    try {
      discovery = await startDiscovery('_worshipcam._tcp');
      discovery.addListener(() {
        if (discovery!.services.isNotEmpty) {
          final service = discovery.services.first;
          final ip = service.host;
          if (ip != null && !completer.isCompleted) {
            stopDiscovery(discovery);
            completer.complete(ip);
          }
        }
      });

      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          if (discovery != null) stopDiscovery(discovery);
          completer.complete(null);
        }
      });
    } catch (e) {
      debugPrint('Error mDNS: $e');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    return completer.future;
  }
}
