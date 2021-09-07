import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient setup(String uniqueID) {
  //mqtt.dioty.co(1883)  broker.hivemq.com(1883)   test.mosquitto.org (1883)  broker.emqx.io(1883)
  return MqttServerClient.withPort('test.mosquitto.org', uniqueID+'_App', 1883);
}