import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RemoteControlClient {
  @visibleForTesting
  WebSocketChannel? channel;
  
  bool isConnected = false;
  
  final Function() onConnected;
  final Function() onDisconnected;
  final Function(String error)? onError;

  RemoteControlClient({
    required this.onConnected,
    required this.onDisconnected,
    this.onError,
  });

  void connect(String ipStr) {
    if (ipStr.contains(':')) {
      ipStr = ipStr.split(':')[0];
    }
    
    final url = 'ws://$ipStr:8080/control';
    try {
      channel = WebSocketChannel.connect(Uri.parse(url));
      
      // Enviar un mensaje de ping o identificación inicial
      sendCommand('ping', 'windows_client');
      
      isConnected = true;
      onConnected();

      channel!.stream.listen(
        (message) {
          debugPrint('Mensaje recibido del celular: $message');
        },
        onDone: () {
          isConnected = false;
          onDisconnected();
        },
        onError: (error) {
          debugPrint('Error en WebSocket: $error');
          isConnected = false;
          if (onError != null) onError!(error.toString());
        },
      );
    } catch (e) {
      debugPrint('Error de conexión: $e');
      isConnected = false;
      if (onError != null) onError!(e.toString());
    }
  }

  void disconnect() {
    channel?.sink.close();
    isConnected = false;
    onDisconnected();
  }

  void sendCommand(String type, dynamic value) {
    if (channel != null && isConnected) {
      final msg = jsonEncode({'type': type, 'value': value});
      channel!.sink.add(msg);
      debugPrint('Enviando comando: $msg');
    }
  }
}

