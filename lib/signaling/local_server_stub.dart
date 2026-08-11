class LocalSignalingServer {
  Function(Map<String, dynamic>)? onMessageReceived;
  Function()? onClientConnected;
  Function()? onClientDisconnected;

  Future<void> start() async {}
  
  void sendMessage(Map<String, dynamic> message) {}
}
