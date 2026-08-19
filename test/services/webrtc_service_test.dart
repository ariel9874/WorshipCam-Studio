import 'package:flutter_test/flutter_test.dart';
import 'package:camo_clone/services/webrtc_service.dart';

void main() {
  group('WebRTCService', () {
    test('mungeSdp inyecta b=AS:15000 justo debajo de m=video', () {
      const originalSdp = '''v=0\r
o=- 4611735165215682163 2 IN IP4 127.0.0.1\r
s=-\r
t=0 0\r
a=group:BUNDLE 0 1\r
m=audio 9 UDP/TLS/RTP/SAVPF 111 103 104 9 0 8 106 105 13 110 112 113 126\r
c=IN IP4 0.0.0.0\r
a=rtcp:9 IN IP4 0.0.0.0\r
m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99 100 101 102 122 127 121 125 107 108 109 124 120 119 114\r
c=IN IP4 0.0.0.0\r
a=rtcp:9 IN IP4 0.0.0.0\r
a=ice-ufrag:abcdef\r
a=ice-pwd:xyz''';

      final modifiedSdp = WebRTCService.mungeSdp(originalSdp);

      final lines = modifiedSdp.split('\r\n');
      
      // Encontrar el índice de m=video
      int videoIndex = lines.indexWhere((line) => line.startsWith('m=video '));
      expect(videoIndex, greaterThan(-1), reason: 'm=video debe existir');
      
      // La siguiente línea DEBE ser b=AS:15000
      expect(lines[videoIndex + 1], 'b=AS:15000', reason: 'b=AS:15000 no se inyectó en el lugar correcto');
    });

    test('mungeSdp no modifica nada si no hay m=video', () {
      const audioOnlySdp = '''v=0\r
o=- 4611735165215682163 2 IN IP4 127.0.0.1\r
s=-\r
t=0 0\r
a=group:BUNDLE 0\r
m=audio 9 UDP/TLS/RTP/SAVPF 111 103\r
c=IN IP4 0.0.0.0\r
''';
      final modifiedSdp = WebRTCService.mungeSdp(audioOnlySdp);
      expect(modifiedSdp, audioOnlySdp);
    });
  });
}
