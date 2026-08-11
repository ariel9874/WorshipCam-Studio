import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({Key? key}) : super(key: key);

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.239');
  WebSocketChannel? _channel;
  bool _isConnected = false;

  void _connect() {
    if (_ipController.text.isEmpty) return;

    final url = 'ws://${_ipController.text}:8080/control';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      // Enviar un mensaje de ping o identificación inicial
      _sendCommand('ping', 'windows_client');
      
      setState(() {
        _isConnected = true;
      });

      _channel!.stream.listen(
        (message) {
          debugPrint('Mensaje recibido del celular: $message');
        },
        onDone: () {
          setState(() {
            _isConnected = false;
          });
        },
        onError: (error) {
          debugPrint('Error en WebSocket: $error');
          setState(() {
            _isConnected = false;
          });
        },
      );
    } catch (e) {
      debugPrint('Error de conexión: $e');
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _isConnected = false;
    });
  }

  void _sendCommand(String type, dynamic value) {
    if (_channel != null && _isConnected) {
      final msg = jsonEncode({'type': type, 'value': value});
      _channel!.sink.add(msg);
      debugPrint('Enviando comando: $msg');
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E), // Dark theme
      appBar: AppBar(
        title: const Text('WorshipCam Remote Panel'),
        backgroundColor: const Color(0xFF282A36),
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
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection Section
              Card(
                color: const Color(0xFF282A36),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text("Conexión a Celular", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ipController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'IP del celular (ej. 192.168.1.15)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _isConnected ? _disconnect : _connect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnected ? Colors.redAccent : Colors.blueAccent,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: Text(_isConnected ? 'Desconectar' : 'Conectar'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Control Section (Only enabled if connected)
              Opacity(
                opacity: _isConnected ? 1.0 : 0.5,
                child: Card(
                  color: const Color(0xFF282A36),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text("Panel de Control Remoto", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        
                        // Switch Lens Button
                        ElevatedButton.icon(
                          onPressed: _isConnected ? () => _sendCommand('switch_lens', 'next') : null,
                          icon: const Icon(Icons.cameraswitch),
                          label: const Text('Cambiar Lente Físico'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Resolution Selector
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Calidad WebRTC:", style: TextStyle(color: Colors.white)),
                            DropdownButton<String>(
                              dropdownColor: Colors.black87,
                              value: 'veryHigh', // Por defecto
                              style: const TextStyle(color: Colors.white),
                              items: const [
                                DropdownMenuItem(value: 'high', child: Text('720p (High)')),
                                DropdownMenuItem(value: 'veryHigh', child: Text('1080p (VeryHigh)')),
                                DropdownMenuItem(value: 'max', child: Text('Máxima')),
                              ],
                              onChanged: _isConnected ? (val) {
                                _sendCommand('set_resolution', val);
                              } : null,
                            ),
                          ],
                        ),

                        // FPS Selector
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Velocidad (FPS):", style: TextStyle(color: Colors.white)),
                            DropdownButton<int>(
                              dropdownColor: Colors.black87,
                              value: 30, // Por defecto
                              style: const TextStyle(color: Colors.white),
                              items: const [
                                DropdownMenuItem(value: 30, child: Text('30 FPS')),
                                DropdownMenuItem(value: 60, child: Text('60 FPS')),
                              ],
                              onChanged: _isConnected ? (val) {
                                _sendCommand('set_fps', val);
                              } : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
