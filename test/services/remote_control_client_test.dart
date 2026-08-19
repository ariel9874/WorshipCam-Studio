import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:camo_clone/services/remote_control_client.dart';

class MockWebSocketSink extends Mock implements WebSocketSink {}
class MockWebSocketChannel extends Mock implements WebSocketChannel {}

void main() {
  group('RemoteControlClient', () {
    late RemoteControlClient client;
    late MockWebSocketChannel mockChannel;
    late MockWebSocketSink mockSink;

    setUp(() {
      mockChannel = MockWebSocketChannel();
      mockSink = MockWebSocketSink();
      when(() => mockChannel.sink).thenReturn(mockSink);

      client = RemoteControlClient(
        onConnected: () {},
        onDisconnected: () {},
      );
      
      client.channel = mockChannel;
      client.isConnected = true;
    });

    test('sendCommand serializa y envía JSON correctamente', () {
      client.sendCommand('set_resolution', 'max');
      
      final expectedJson = jsonEncode({'type': 'set_resolution', 'value': 'max'});
      verify(() => mockSink.add(expectedJson)).called(1);
    });

    test('sendCommand con valores enteros funciona correctamente', () {
      client.sendCommand('set_fps', 60);
      
      final expectedJson = jsonEncode({'type': 'set_fps', 'value': 60});
      verify(() => mockSink.add(expectedJson)).called(1);
    });
  });
}
