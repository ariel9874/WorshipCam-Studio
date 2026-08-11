import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'web_client.dart';

class LocalSignalingServer {
  final int port = 8080;
  WebSocketChannel? _obsChannel;
  
  // Callbacks para comunicar con main.dart
  Function(Map<String, dynamic>)? onMessageReceived;
  Function()? onClientConnected;
  Function()? onClientDisconnected;

  Future<void> start() async {
    final router = Router();

    // 1. Ruta HTTP principal: OBS carga esta página HTML secreta
    router.get('/', (Request request) {
      return Response.ok(webClientHtml, headers: {'Content-Type': 'text/html'});
    });

    // 2. Ruta WebSocket: OBS se conecta aquí para negociar el video
    router.get('/ws', webSocketHandler((webSocket, protocol) {
      _obsChannel = webSocket;
      debugPrint("OBS conectado vía WebSocket!");
      onClientConnected?.call();

      webSocket.stream.listen((message) {
        final data = jsonDecode(message);
        onMessageReceived?.call(data);
      }, onDone: () {
        debugPrint("OBS desconectado");
        _obsChannel = null;
        onClientDisconnected?.call();
      });
    }));

    // Iniciar el servidor escuchando en todas las interfaces de red (0.0.0.0)
    await io.serve(router.call, '0.0.0.0', port);
    debugPrint('Servidor Local corriendo en puerto $port');
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_obsChannel != null) {
      _obsChannel!.sink.add(jsonEncode(message));
    } else {
      debugPrint("Error: Intentando enviar mensaje WebRTC pero OBS no está conectado.");
    }
  }
}
