import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient setup(String uniqueID) {
  return MqttBrowserClient.withPort('ws://broker.emqx.io', uniqueID+'_web', 8083);
}