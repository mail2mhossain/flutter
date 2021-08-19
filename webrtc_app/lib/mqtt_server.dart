import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient setup(String uniqueID) {
  return MqttServerClient.withPort('test.mosquitto.org', uniqueID+'_App', 1883);
}