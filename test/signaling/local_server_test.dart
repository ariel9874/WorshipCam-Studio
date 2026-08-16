import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:camo_clone/signaling/local_server.dart';

void main() {
  late LocalSignalingServer server;

  setUp(() async {
    server = LocalSignalingServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  test('El servidor inicia y acepta conexiones WebSocket WebRTC', () async {
    bool connected = false;
    server.onClientConnected = (clientId) {
      connected = true;
    };

    final wsUrl = Uri.parse('ws://127.0.0.1:8080/ws');
    final channel = WebSocketChannel.connect(wsUrl);
    
    // Esperar a que el servidor registre la conexión
    await Future.delayed(const Duration(milliseconds: 100));

    expect(connected, isTrue);
    expect(server.webrtcClients.length, 1);
    
    await channel.sink.close();
  });

  test('Mutex funciona: Conectar un segundo cliente desconecta al primero', () async {
    final wsUrl = Uri.parse('ws://127.0.0.1:8080/ws');
    
    // Cliente 1
    final channel1 = WebSocketChannel.connect(wsUrl);
    await Future.delayed(const Duration(milliseconds: 100));
    expect(server.webrtcClients.length, 1);

    // Enviar un mensaje dummy para ver si la conexión sigue viva
    channel1.sink.add(jsonEncode({'type': 'dummy'}));

    // Cliente 2
    final channel2 = WebSocketChannel.connect(wsUrl);
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Debería seguir habiendo solo 1 cliente en el mapa
    expect(server.webrtcClients.length, 1);

    // Enviar algo por el channel1 debería fallar o ser ignorado porque el servidor cerró el socket
    var didChannel1Close = false;
    channel1.stream.listen((event) {}, onDone: () {
      didChannel1Close = true;
    });

    await Future.delayed(const Duration(milliseconds: 100));
    expect(didChannel1Close, isTrue);

    await channel2.sink.close();
  });

  test('Enrutamiento de mensajes JSON funciona', () async {
    String? receivedMessage;
    server.onMessageReceived = (clientId, message) {
      receivedMessage = message['type'];
    };

    final wsUrl = Uri.parse('ws://127.0.0.1:8080/ws');
    final channel = WebSocketChannel.connect(wsUrl);
    await Future.delayed(const Duration(milliseconds: 100));

    channel.sink.add(jsonEncode({'type': 'offer', 'data': '123'}));
    await Future.delayed(const Duration(milliseconds: 100));

    expect(receivedMessage, 'offer');
    await channel.sink.close();
  });
}
