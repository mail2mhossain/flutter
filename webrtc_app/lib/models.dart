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
  REQUEST_ICE_CANDIDATES,
  ICE_CANDIDATES
}