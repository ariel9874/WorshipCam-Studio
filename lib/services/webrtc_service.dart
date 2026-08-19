import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;

  Future<void> startConnection({
    required MediaStream localStream,
    required String localIp,
    required Function(Map<String, dynamic>) onSendMessage,
  }) async {
    final configuration = {
      'iceServers': [] // Vacío para forzar conexión 100% local (offline)
    };

    peerConnection = await createPeerConnection(configuration);

    peerConnection!.onIceCandidate = (candidate) {
      String modifiedCandidate = candidate.candidate ?? "";
      
      // Solución para el bug de WebRTC en Android Hotspot:
      // libwebrtc ignora la interfaz ap0 (Hotspot) y solo devuelve 127.0.0.1.
      // Reemplazamos 127.0.0.1 con la IP real del Hotspot para que OBS sepa a dónde enviar.
      if (modifiedCandidate.contains('127.0.0.1') && localIp != "No conectado a Wi-Fi") {
        modifiedCandidate = modifiedCandidate.replaceAll('127.0.0.1', localIp);
      }

      onSendMessage({
        'type': 'candidate',
        'candidate': {
          'candidate': modifiedCandidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      });
    };

    // Añadir tracks usando addTransceiver (Unified Plan)
    for (var track in localStream.getVideoTracks()) {
      await peerConnection!.addTransceiver(
        track: track,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendOnly,
          streams: [localStream],
        ),
      );
    }

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": false,
        "OfferToReceiveVideo": false,
      },
      "optional": [],
    };
    final offer = await peerConnection!.createOffer(offerSdpConstraints);
    
    String modifiedSdp = offer.sdp ?? "";
    if (localIp != "No conectado a Wi-Fi") {
      modifiedSdp = modifiedSdp.replaceAll('127.0.0.1', localIp);
      modifiedSdp = modifiedSdp.replaceAll('0.0.0.0', localIp);
    }
    
    // Forzar un bitrate muy alto para video (15 Mbps)
    modifiedSdp = mungeSdp(modifiedSdp);

    await peerConnection!.setLocalDescription(RTCSessionDescription(modifiedSdp, offer.type));

    onSendMessage({
      'type': 'offer',
      'offer': {
        'type': offer.type,
        'sdp': modifiedSdp
      }
    });
  }

  @visibleForTesting
  static String mungeSdp(String sdp) {
    final lines = sdp.split('\r\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('m=video ')) {
        lines.insert(i + 1, 'b=AS:15000');
        break;
      }
    }
    return lines.join('\r\n');
  }

  Future<void> handleAnswer(Map<String, dynamic> answerMap) async {
    final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
    await peerConnection?.setRemoteDescription(answer);
  }

  Future<void> handleCandidate(Map<String, dynamic> candidateMap, String clientIp) async {
    String candStr = candidateMap['candidate'] as String;
    
    // ¡LA ESTOCADA FINAL AL BUG DE WEBRTC!
    // Si el PC nos envió su IP oculta en mDNS (.local), la descubrimos nosotros mismos
    // usando la IP real desde donde se conectó al WebSocket, y la inyectamos a la fuerza
    // en el candidato ICE para que WebRTC en Android sepa a quién debe contestar.
    if (candStr.contains('.local')) {
      candStr = candStr.replaceAll(RegExp(r'[a-f0-9\-]+\.local'), clientIp);
      debugPrint("¡Candidato mDNS interceptado! Reemplazado por: $clientIp");
    }

    final candidate = RTCIceCandidate(
      candStr,
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );
    await peerConnection?.addCandidate(candidate);
  }

  void stopConnection() {
    peerConnection?.close();
    peerConnection = null;
  }
}
