import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/adb_service.dart';
import '../../services/discovery_service.dart';
import '../../services/remote_control_client.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({Key? key}) : super(key: key);

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  RemoteControlClient? _client;
  bool _isConnected = false;
  bool _isTunnelActive = false;
  bool _isDiscovering = false;

  // WebRTC Monitor
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _webrtcChannel;
  bool _isMonitoring = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _client = RemoteControlClient(
      onConnected: () => setState(() => _isConnected = true),
      onDisconnected: () => setState(() => _isConnected = false),
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
        }
      }
    );
    _setupTunnel();
  }

  Future<void> _setupTunnel() async {
    final success = await AdbService.setupUSBTunnel();
    if (mounted) {
      setState(() => _isTunnelActive = success);
    }
  }

  Future<void> _discoverDevice() async {
    setState(() => _isDiscovering = true);
    final ip = await DiscoveryService.discoverDevice();
    
    if (mounted) {
      setState(() => _isDiscovering = false);
      if (ip != null) {
        _ipController.text = ip;
        _connect();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontraron celulares en la red.')));
      }
    }
  }

  void _connect() {
    if (_ipController.text.isNotEmpty) {
      _client?.connect(_ipController.text);
    }
  }

  void _disconnect() {
    _client?.disconnect();
  }

  Future<void> _startVideoMonitor() async {
    final url = 'ws://${_ipController.text}:8080/ws';
    _webrtcChannel = WebSocketChannel.connect(Uri.parse(url));
    
    final configuration = {'iceServers': []};
    
    _peerConnection = await createPeerConnection(configuration);
    
    _peerConnection!.onIceCandidate = (candidate) {
      _webrtcChannel!.sink.add(jsonEncode({
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      }));
    };
    
    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
        setState(() {});
      }
    };
    
    _webrtcChannel!.stream.listen((message) async {
      final data = jsonDecode(message);
      final type = data['type'];
      
      if (type == 'offer') {
        final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);
        await _peerConnection!.setRemoteDescription(offer);
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        
        _webrtcChannel!.sink.add(jsonEncode({
          'type': 'answer',
          'answer': {
            'type': answer.type,
            'sdp': answer.sdp
          }
        }));
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
      }
    }, onDone: () {
      _stopVideoMonitor();
    });
    
    setState(() {
      _isMonitoring = true;
    });
  }

  void _stopVideoMonitor() {
    _webrtcChannel?.sink.close();
    _peerConnection?.close();
    _remoteRenderer.srcObject = null;
    setState(() {
      _isMonitoring = false;
    });
  }

  @override
  void dispose() {
    _client?.disconnect();
    _webrtcChannel?.sink.close();
    _peerConnection?.close();
    _remoteRenderer.dispose();
    _ipController.dispose();
    
    if (_isTunnelActive) {
      AdbService.removeUSBTunnel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('WorshipCam Remote Panel'),
        backgroundColor: const Color(0xFF282A36).withValues(alpha: 0.8),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                _isConnected ? "CONECTADO" : "DESCONECTADO",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Row(
          children: [
            // Área de Video
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)
                  ]
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isMonitoring)
                        RTCVideoView(
                          _remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        )
                      else
                        const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_off, color: Colors.white54, size: 60),
                              SizedBox(height: 10),
                              Text("Video Monitor Inactivo", style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                      
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: _isMonitoring ? Colors.red : Colors.blueAccent,
                          onPressed: () {
                            if (_isMonitoring) {
                              _stopVideoMonitor();
                            } else {
                              if (_ipController.text.isNotEmpty) {
                                _startVideoMonitor();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa la IP primero')));
                              }
                            }
                          },
                          child: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow, color: Colors.white),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),

            // Panel de Control
            Container(
              width: 350,
              decoration: BoxDecoration(
                color: const Color(0xFF282A36).withValues(alpha: 0.95),
                border: const Border(left: BorderSide(color: Colors.white12)),
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text("CONEXIÓN", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'IP del Celular',
                            labelStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.black54,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _isDiscovering ? null : _discoverDevice,
                        icon: _isDiscovering 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search, color: Colors.blueAccent),
                        tooltip: "Buscar en Wi-Fi",
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.redAccent : Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: _isConnected ? _disconnect : _connect,
                    child: Text(_isConnected ? "DESCONECTAR" : "CONECTAR", style: const TextStyle(color: Colors.white)),
                  ),
                  
                  const SizedBox(height: 30),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),

                  const Text("CÁMARA", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  _buildControlCard(
                    title: "Cambiar Lente",
                    icon: Icons.cameraswitch,
                    onTap: () => _client?.sendCommand('switch_lens', null),
                  ),
                  
                  _buildControlCard(
                    title: "Activar/Desactivar Flash",
                    icon: Icons.flash_on,
                    onTap: () => _client?.sendCommand('toggle_flash', null),
                  ),

                  const SizedBox(height: 20),
                  const Text("CALIDAD", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  _buildDropdownRow(
                    title: "Resolución:",
                    items: const ['max', 'ultraHigh', 'veryHigh', 'high', 'medium', 'low'],
                    onChanged: (val) => _client?.sendCommand('set_resolution', val),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  _buildDropdownRow(
                    title: "FPS:",
                    items: const ['24', '30', '60'],
                    onChanged: (val) => _client?.sendCommand('set_fps', int.parse(val)),
                  ),
                  
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard({required String title, required IconData icon, required VoidCallback onTap}) {
    return Card(
      color: Colors.black54,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: _isConnected ? onTap : null,
        enabled: _isConnected,
      ),
    );
  }

  Widget _buildDropdownRow({required String title, required List<String> items, required Function(String) onChanged}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white)),
        DropdownButton<String>(
          dropdownColor: Colors.black87,
          style: const TextStyle(color: Colors.white),
          hint: const Text("Sel", style: TextStyle(color: Colors.white54)),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(),
          onChanged: _isConnected ? (val) {
            if (val != null) onChanged(val);
          } : null,
        ),
      ],
    );
  }
}
