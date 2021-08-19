enum MqttCurrentConnectionState {
  IDLE,
  CONNECTING,
  CONNECTED,
  DISCONNECTED,
  ERROR_WHEN_CONNECTING
}

enum MqttSubscriptionState {
  IDLE,
  SUBSCRIBED
}

enum WebRTC_Method {
  OFFER,
  ANSWER,
  ICE_CANDIDATE
}