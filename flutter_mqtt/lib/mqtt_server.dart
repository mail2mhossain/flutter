import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient setup(String uniqueID) {
  return MqttServerClient.withPort('broker.emqx.io', uniqueID+'_App', 1883);
}