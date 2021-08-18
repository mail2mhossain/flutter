import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_server.dart' if (dart.library.html) 'mqtt_browser.dart'
    as mqttsetup;
import 'models.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter WebRTC Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // set default sub and conn states
  MqttCurrentConnectionState connectionState = MqttCurrentConnectionState.IDLE;
  MqttSubscriptionState subscriptionState = MqttSubscriptionState.IDLE;

  final _client = mqttsetup.setup('broker.emqx.io');

  final _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  @override
  dispose() {
    _localStream?.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    initRenderers();
    _getUserMedia();
    prepareMqttClient();
  }

  initRenderers() async {
    await _localRenderer.initialize();
  }

  _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth':
              '100', // Provide your own width, height and frame rate here
          'minHeight': '70',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

    _localRenderer.srcObject = _localStream;
  }

  void prepareMqttClient() async {
    _setupMqttClient();
    await _connectClient();
    _subscribeToTopic('new_registration');
  }

  /// sets up mqtt client and connection params
  void _setupMqttClient() {
    //_client.logging(on: false);
    _client.keepAlivePeriod = 20;
    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;
    _client.onSubscribed = _onSubscribed;
  }

  // method to establish connection to mqtt server
  Future<void> _connectClient() async {
    try {
      // set connection state to connecting
      print('Mosquitto client connecting....');
      connectionState = MqttCurrentConnectionState.CONNECTING;

      // establish the connection
      await _client.connect();
    } on Exception catch (e) {
      // set connection state to err while connecting
      print('client exception - $e');
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;

      // disconnect from client instance
      _client.disconnect();
    }

    // check the connection state
    if (_client.connectionStatus!.state == MqttConnectionState.connected) {
      // set connection state to connected
      connectionState = MqttCurrentConnectionState.CONNECTED;
      print('Mosquitto client connected');
    } else {
      print(
          'ERROR Mosquitto client connection failed - disconnecting, status is ${_client.connectionStatus}');

      // set connection state to err while connecting and disconnect from instance
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      _client.disconnect();
    }
  }

  void _subscribeToTopic(String topicName) {
    print('Subscribing to the $topicName topic');
    // subscribe
    _client.subscribe(topicName, MqttQos.atMostOnce);

    // listen
    _client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      print(
          'New Message Arrived:: topic is <${c[0].topic}>, payload is <-- $pt -->');
    });
  }

  /// called when client subscribes to topic
  void _onSubscribed(String topic) {
    print('Subscription confirmed for topic $topic');
    subscriptionState = MqttSubscriptionState.SUBSCRIBED;
  }

  /// called when mqtt server disconnects.
  void _onDisconnected() {
    print('OnDisconnected client callback - Client disconnection');

    connectionState = MqttCurrentConnectionState.DISCONNECTED;
  }

  /// called when mqtt server is connected
  void _onConnected() {
    connectionState = MqttCurrentConnectionState.CONNECTED;
    print('OnConnected client callback - Client connection was sucessful');
    //onConnectedCallback();
  }

  /// Published new location to mqtt
  void _publishMessage() {
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    String message = 'Message From Flutter';
    builder.addString(message);

    _client.publishMessage(
        'new_registration', MqttQos.exactlyOnce, builder.payload!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: RTCVideoView(_localRenderer, mirror: true),
              decoration: BoxDecoration(color: Colors.black54),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _publishMessage,
        tooltip: 'Publish Message',
        child: const Icon(Icons.add),
      ),
    );
  }
}
