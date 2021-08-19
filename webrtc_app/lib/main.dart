import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sdp_transform/sdp_transform.dart';
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
  bool _offer = false;
  List<String> ICE_candidates = [];
  final String myMobile = "01713032885"; //"01713032885";
  final String anotherMobile = "09638582706"; //"09638582706";
  // set default sub and conn states
  MqttCurrentConnectionState connectionState = MqttCurrentConnectionState.IDLE;
  MqttSubscriptionState subscriptionState = MqttSubscriptionState.IDLE;

  final _client = mqttsetup.setup("01713032885");

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  @override
  dispose() {
    _localStream?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    prepareMqttClient();
    initRenderers();
    _createPeerConnecion().then((pc) {
      _peerConnection = pc;
    });
    super.initState();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _createPeerConnecion() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _localStream = await _getUserMedia();

    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);

    pc.addStream(_localStream!);

    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        String candidate = json.encode({
          'candidate': e.candidate.toString(),
          'sdpMid': e.sdpMid.toString(),
          'sdpMlineIndex': e.sdpMlineIndex,
        });
        ICE_candidates.add(candidate);
        print("ICE Candidate has been generated");
      }
    };

    pc.onIceConnectionState = (e) {
      //print(e);
    };

    pc.onAddStream = (stream) {
      //print('addStream: ' + stream.id);
      _remoteRenderer.srcObject = stream;
    };

    return pc;
  }

  _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
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

    MediaStream stream =
        await navigator.mediaDevices.getUserMedia(mediaConstraints);

    _localRenderer.srcObject = stream;
    return stream;
  }

  void _createOffer() async {
    RTCSessionDescription description =
        await _peerConnection!.createOffer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp.toString());
    String offerSdp = json.encode(session);
    _offer = true;
    _peerConnection!.setLocalDescription(description);
    _publishMessage(anotherMobile, WebRTC_Method.OFFER.index, offerSdp);
    print("OFFER messsage has been sent to: $anotherMobile");
  }

  void _setRemoteDescription(String sdpString) async {
    RTCSessionDescription description =
        RTCSessionDescription(sdpString, _offer ? 'answer' : 'offer');

    await _peerConnection!.setRemoteDescription(description);

    if (_offer) {
      print("Remote Description has been set as ANSWER");
      int totalICECandidates = ICE_candidates.length;
      print("Total ICE Candidates: $totalICECandidates");
      for (var candidate in ICE_candidates) {
        _publishMessage(
            anotherMobile, WebRTC_Method.ICE_CANDIDATE.index, candidate);
      }

      print("Candidate message has been published to: $anotherMobile");
      _offer = false;
    } else {
      print("Remote Description has been set as OFFER");
    }
  }

  void _createAnswer() async {
    RTCSessionDescription description =
        await _peerConnection!.createAnswer({'offerToReceiveVideo': 1});

    var session = parse(description.sdp.toString());
    String answerSdp = json.encode(session);

    _peerConnection!.setLocalDescription(description);
    _publishMessage(anotherMobile, WebRTC_Method.ANSWER.index, answerSdp);
    print("ANSWER message has been sent to: $anotherMobile");
  }

  void _addCandidate(Map<String, dynamic> candidates) async {
    //print('Received Candidate: $candidates');
    dynamic candidate = RTCIceCandidate(candidates['candidate'],
        candidates['sdpMid'], candidates['sdpMlineIndex']);
    await _peerConnection!.addCandidate(candidate);
    print("CANDIDATE has been added.");
  }

  void prepareMqttClient() async {
    _setupMqttClient();
    await _connectClient();
    _subscribeToTopic(myMobile);
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

      var receivedMessage = json.decode(pt);
      String sdp = "";

      if (receivedMessage['Type'] == WebRTC_Method.OFFER.index) {
        print("OFFER Message has been Received");
        _offer = false;
        sdp = write(receivedMessage['Body'], null);
        _setRemoteDescription(sdp);
        _createAnswer();
      }
      if (receivedMessage['Type'] == WebRTC_Method.ANSWER.index) {
        print("ANSWER Message has been Received");
        sdp = write(receivedMessage['Body'], null);
        _setRemoteDescription(sdp);
      }
      if (receivedMessage['Type'] == WebRTC_Method.ICE_CANDIDATE.index) {
        print("CANDIDATE Message has been Received");
        _addCandidate(receivedMessage['Body']);
      }
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
  void _publishMessage(String topic, int webRTCMethod, String sdp) {
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    String message = '{"Type":$webRTCMethod, "Body":$sdp}';
    builder.addString(message);

    _client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
  }

  SizedBox videoRenderers() => SizedBox(
      height: 210,
      child: Row(children: [
        Flexible(
          child: Container(
              key: const Key("local"),
              margin: const EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: const BoxDecoration(color: Colors.black),
              child: RTCVideoView(_localRenderer)),
        ),
        Flexible(
          child: Container(
              key: const Key("remote"),
              margin: const EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: const BoxDecoration(color: Colors.black),
              child: RTCVideoView(_remoteRenderer)),
        )
      ]));

  Row offerAndAnswerButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        ElevatedButton(
          onPressed: _createOffer,
          child: const Text('Make Call'),
        ),
        ElevatedButton(
          onPressed: _createAnswer,
          child: const Text('Answer'),
          //style: ElevatedButton.styleFrom(primary: Colors.amber),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
          child: Column(
        children: [
          videoRenderers(),
          offerAndAnswerButtons(),
          //sdpCandidatesTF(),
          //sdpCandidateButtons(),
        ],
      )),
    );
  }
}
