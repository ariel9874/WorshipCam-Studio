import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialService {
  SerialPort? _port;
  SerialPortReader? _reader;
  bool isConnected = false;
  
  // Stream de eventos desde el ESP32 hacia Flutter
  final _messageController = StreamController<String>.broadcast();
  Stream<String> get onMessage => _messageController.stream;

  /// Obtiene la lista de puertos COM disponibles
  List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }

  /// Conecta al puerto COM especificado (ej. "COM3" o "/dev/ttyUSB0")
  bool connect(String portName, {int baudRate = 115200}) {
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        debugPrint(SerialPort.lastError.toString());
        return false;
      }

      // Configurar velocidad
      SerialPortConfig config = _port!.config;
      config.baudRate = baudRate;
      _port!.config = config;

      // Iniciar el Lector (Reader)
      _reader = SerialPortReader(_port!);
      _reader!.stream.listen((data) {
        String message = String.fromCharCodes(data).trim();
        if (message.isNotEmpty) {
          _messageController.add(message);
        }
      });

      isConnected = true;
      debugPrint("Conectado exitosamente al Maestro ESP32 en $portName");
      return true;
    } catch (e) {
      debugPrint("Error conectando al puerto serial: $e");
      return false;
    }
  }

  /// Desconecta el puerto
  void disconnect() {
    _reader?.close();
    _reader = null;
    
    if (_port != null && _port!.isOpen) {
      _port!.close();
      _port!.dispose();
    }
    _port = null;
    isConnected = false;
    debugPrint("Puerto serial desconectado.");
  }

  /// Envía un comando de texto al ESP32 (terminado en salto de línea)
  void sendCommand(String command) {
    if (!isConnected || _port == null) return;
    
    try {
      // El ESP32 leerá hasta encontrar el salto de línea '\n'
      final String payload = "$command\n";
      final Uint8List bytes = Uint8List.fromList(payload.codeUnits);
      _port!.write(bytes);
      debugPrint("Serial enviado: $command");
    } catch (e) {
      debugPrint("Error enviando por serial: $e");
    }
  }
}
