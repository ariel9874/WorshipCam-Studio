import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkUtils {
  static Future<String> fetchLocalIp() async {
    String? foundIp;
    try {
      foundIp = await NetworkInfo().getWifiIP();
      if (foundIp == null || foundIp == "127.0.0.1" || foundIp.isEmpty) {
        final interfaces = await NetworkInterface.list();
        
        // Prioridades: 1. USB Tethering, 2. Hotspot Wi-Fi, 3. Wi-Fi Client
        final preferredNames = ['rndis0', 'usb0', 'ap0', 'swlan0', 'wlan0'];
        
        for (var name in preferredNames) {
          for (var interface in interfaces) {
            if (interface.name.toLowerCase().startsWith(name)) {
              for (var addr in interface.addresses) {
                if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
                  foundIp = addr.address;
                  break;
                }
              }
            }
            if (foundIp != null) break;
          }
          if (foundIp != null) break;
        }

        // Fallback: Cualquier interfaz que no sea loopback ni red celular (rmnet)
        if (foundIp == null) {
          for (var interface in interfaces) {
            if (interface.name.toLowerCase().startsWith('rmnet')) continue;
            for (var addr in interface.addresses) {
              if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
                foundIp = addr.address;
                break;
              }
            }
            if (foundIp != null) break;
          }
        }
      }
    } catch (e) {
      debugPrint("Error obteniendo IP: $e");
    }
    
    return foundIp ?? "127.0.0.1";
  }
}
