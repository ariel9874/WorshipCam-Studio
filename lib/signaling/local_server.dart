import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'web_client.dart';

import 'dart:io';
import 'package:nsd/nsd.dart';

class LocalSignalingServer {
  final int port = 8080;
  final Map<String, WebSocketChannel> webrtcClients = {};
  HttpServer? _httpServer;
  Registration? _nsdRegistration;
  
  // Callbacks para comunicar con main.dart (WebRTC)
  Function(String clientId, String clientIp, Map<String, dynamic> message)? onMessageReceived;
  Function(String clientId)? onClientConnected;
  Function(String clientId)? onClientDisconnected;

  // Callbacks para el Control Remoto
  Function(Map<String, dynamic> message)? onRemoteCommandReceived;
  Function(bool connected)? onRemoteControlStatusChanged;

  void broadcastVideoFrame(Uint8List frame) {
    for (var client in webrtcClients.values) {
      client.sink.add(frame);
    }
  }

  Future<void> start() async {
    final router = Router();

    // 1. Ruta HTTP principal: OBS carga esta página HTML secreta
    router.get('/', (Request request) {
      return Response.ok(webClientHtml, headers: {'Content-Type': 'text/html'});
    });

    // 2. Ruta WebSocket: Clientes de Video (OBS y Windows App)
    router.get('/ws', (Request request) {
      final info = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final clientIp = info?.remoteAddress.address ?? '127.0.0.1';

      final handler = webSocketHandler((webSocket, protocol) {
        // Mutex: Desconectar clientes anteriores
        final oldClients = webrtcClients.values.toList();
        for (var client in oldClients) {
          client.sink.close();
        }
        webrtcClients.clear();

        final clientId = DateTime.now().millisecondsSinceEpoch.toString();
        webrtcClients[clientId] = webSocket;
        
        debugPrint("Cliente WebRTC conectado: $clientId (IP: $clientIp)");
        onClientConnected?.call(clientId);

        webSocket.stream.listen((message) {
          final data = jsonDecode(message);
          onMessageReceived?.call(clientId, clientIp, data);
        }, onDone: () {
          debugPrint("Cliente WebRTC desconectado: $clientId");
          webrtcClients.remove(clientId);
          onClientDisconnected?.call(clientId);
        });
      });
      return handler(request);
    });

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
    _httpServer = await io.serve(router.call, '0.0.0.0', port);
    debugPrint('Servidor Local corriendo en puerto $port');

    try {
      _nsdRegistration = await register(const Service(
        name: 'WorshipCam',
        type: '_worshipcam._tcp',
        port: 8080,
      ));
      debugPrint('Servicio mDNS registrado: ${_nsdRegistration?.service.name}');
    } catch (e) {
      debugPrint('Error registrando mDNS: $e');
    }
  }

  Future<void> stop() async {
    final clients = webrtcClients.values.toList();
    for (var client in clients) {
      client.sink.close();
    }
    webrtcClients.clear();
    
    if (_nsdRegistration != null) {
      try {
        await unregister(_nsdRegistration!);
        _nsdRegistration = null;
      } catch (e) {
        debugPrint('Error quitando mDNS: $e');
      }
    }
    await _httpServer?.close(force: true);
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
