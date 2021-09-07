import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient setup(String uniqueID) {
  //mqtt.dioty.co(8080)  broker.hivemq.com(8000)   test.mosquitto.org (8080)  broker.emqx.io (8083)
  return MqttBrowserClient.withPort('ws://test.mosquitto.org', uniqueID+'_web', 8080);
}