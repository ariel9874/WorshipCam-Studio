import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../services/remote_control_client.dart';

class CameraNode {
  final String ip;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RemoteControlClient? client;
  WebSocketChannel? webrtcChannel;
  RTCPeerConnection? peerConnection;
  bool isConnected = false;
  bool isMonitoring = false;

  CameraNode({required this.ip});

  Future<void> initialize() async {
    await renderer.initialize();
  }

  void dispose() {
    client?.disconnect();
    webrtcChannel?.sink.close();
    peerConnection?.close();
    renderer.dispose();
  }
}
