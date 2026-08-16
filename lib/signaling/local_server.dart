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
  final Map<String, WebSocketChannel> webrtcClients = {};
  
  // Callbacks para comunicar con main.dart (WebRTC)
  Function(String clientId, Map<String, dynamic> message)? onMessageReceived;
  Function(String clientId)? onClientConnected;
  Function(String clientId)? onClientDisconnected;

  // Callbacks para el Control Remoto
  Function(Map<String, dynamic> message)? onRemoteCommandReceived;
  Function(bool connected)? onRemoteControlStatusChanged;

  Future<void> start() async {
    final router = Router();

    // 1. Ruta HTTP principal: OBS carga esta página HTML secreta
    router.get('/', (Request request) {
      return Response.ok(webClientHtml, headers: {'Content-Type': 'text/html'});
    });

    // 2. Ruta WebSocket: Clientes de Video (OBS y Windows App)
    router.get('/ws', webSocketHandler((webSocket, protocol) {
      // Mutex: Desconectar clientes anteriores
      for (var client in webrtcClients.values) {
        client.sink.close();
      }
      webrtcClients.clear();

      final clientId = DateTime.now().millisecondsSinceEpoch.toString();
      webrtcClients[clientId] = webSocket;
      
      debugPrint("Cliente WebRTC conectado: $clientId");
      onClientConnected?.call(clientId);

      webSocket.stream.listen((message) {
        final data = jsonDecode(message);
        onMessageReceived?.call(clientId, data);
      }, onDone: () {
        debugPrint("Cliente WebRTC desconectado: $clientId");
        webrtcClients.remove(clientId);
        onClientDisconnected?.call(clientId);
      });
    }));

    // 3. Ruta WebSocket para el Control Remoto (App de Windows)
    router.get('/control', webSocketHandler((webSocket, protocol) {
      debugPrint("Control Remoto conectado!");
      onRemoteControlStatusChanged?.call(true);
      
      webSocket.stream.listen((message) {
        final data = jsonDecode(message);
        onRemoteCommandReceived?.call(data);
      }, onDone: () {
        debugPrint("Control Remoto desconectado");
        onRemoteControlStatusChanged?.call(false);
      });
    }));

    // Iniciar el servidor escuchando en todas las interfaces de red (0.0.0.0)
    await io.serve(router.call, '0.0.0.0', port);
    debugPrint('Servidor Local corriendo en puerto $port');
  }

  void sendMessageToClient(String clientId, Map<String, dynamic> message) {
    if (webrtcClients.containsKey(clientId)) {
      webrtcClients[clientId]!.sink.add(jsonEncode(message));
    }
  }

  void sendMessageToAll(Map<String, dynamic> message) {
    final msg = jsonEncode(message);
    for (var client in webrtcClients.values) {
      client.sink.add(msg);
    }
  }
}
