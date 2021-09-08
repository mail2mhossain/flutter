import 'dart:convert';
import 'dart:async';
import 'dart:core';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_server.dart' if (dart.library.html) 'mqtt_browser.dart'
    as mqttsetup;
import 'models.dart';
import 'constants.dart';

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
  bool _inCalling = false;
  final String myMobile = "09638582706"; //"01713032885";
  final String anotherMobile = "01713032885"; //"09638582706";
  // set default sub and conn states
  MqttCurrentConnectionState connectionState = MqttCurrentConnectionState.IDLE;
  MqttSubscriptionState subscriptionState = MqttSubscriptionState.IDLE;

  final _client = mqttsetup.setup("09638582706");
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  Timer? _timer;

  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  @override
  dispose() {
    super.dispose();
    _localStream?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  @override
  void initState() {
    super.initState();
    prepareMqttClient();
    initRenderers();
  }

  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void handleStatsReport(Timer timer) async {}

  void _onSignalingState(RTCSignalingState state) {
    //print(state);
  }

  void _onIceGatheringState(RTCIceGatheringState state) {
    //print(state);
  }

  void _onIceConnectionState(RTCIceConnectionState state) {
    //print(state);
  }

  void _onPeerConnectionState(RTCPeerConnectionState state) {
    //print(state);
  }

  void _onAddStream(MediaStream stream) {
    //print('New stream: ' + stream.id);
    _remoteRenderer.srcObject = stream;
  }

  void _onRemoveStream(MediaStream stream) {
    _remoteRenderer.srcObject = null;
  }

  void _onIceCandidate(RTCIceCandidate candidate) {
    if (candidate.candidate != null) {
      //print("ICE Candidate has been generated");
      String candidateString = json.encode({
        'candidate': candidate.candidate.toString(),
        'sdpMid': candidate.sdpMid.toString(),
        'sdpMlineIndex': candidate.sdpMlineIndex,
      });
      _sendIceCandidate(candidateString);
    }
  }

  void _onTrack(RTCTrackEvent event) {
    //print('onTrack');
    if (event.track.kind == 'video') {
      _remoteRenderer.srcObject = event.streams[0];
    }
  }

  void _onAddTrack(MediaStream stream, MediaStreamTrack track) {
    if (track.kind == 'video') {
      _remoteRenderer.srcObject = stream;
    }
  }

  void _onRemoveTrack(MediaStream stream, MediaStreamTrack track) {
    if (track.kind == 'video') {
      _remoteRenderer.srcObject = null;
    }
  }

  void _onRenegotiationNeeded() {
    //print('RenegotiationNeeded');
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _makeCall() async {
    if (_peerConnection != null) return;

    await _createPeerConnection();
    var description = await _createOffer();
    _sendOffer(description);
    _peerConnection!.onIceCandidate = _onIceCandidate;
    setState(() {
      _inCalling = true;
    });
  }

  void _receiveCall(String sdpString) async {
    if (_peerConnection != null) {
      _hangUp();
    }

    await _createPeerConnection();
    await _setRemoteDescription(sdpString);
    var sdp = await _createAnswer();
    await _sendAnswer(sdp);
    _peerConnection!.onIceCandidate = _onIceCandidate;
    setState(() {
      _inCalling = false;
    });
  }

  void _hangUp() async {
    try {
      await _localStream?.dispose();
      await _peerConnection?.close();
      _peerConnection = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (e) {
      print("Hang Up Error. ERROR:");
      print(e.toString());
    }
    setState(() {
      _inCalling = false;
    });
    _timer?.cancel();
  }

  _createPeerConnection() async {
    try {
      _peerConnection =
          await createPeerConnection(configuration, offerSdpConstraints);

      _peerConnection!.onSignalingState = _onSignalingState;
      _peerConnection!.onConnectionState = _onPeerConnectionState;
      _peerConnection!.onIceConnectionState = _onIceConnectionState;
      _peerConnection!.onIceGatheringState = _onIceGatheringState;
      //_peerConnection!.onIceCandidate = _onIceCandidate;
      _peerConnection!.onRenegotiationNeeded = _onRenegotiationNeeded;

      _localStream =
          await navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
      _localRenderer.srcObject = _localStream;
      _remoteRenderer.srcObject = await createLocalMediaStream('key');

      switch (sdpSemantics) {
        case 'plan-b':
          _peerConnection!.onAddStream = _onAddStream;
          _peerConnection!.onRemoveStream = _onRemoveStream;
          await _peerConnection!.addStream(_localStream!);
          break;
        case 'unified-plan':
          _peerConnection!.onTrack = _onTrack;
          _peerConnection!.onAddTrack = _onAddTrack;
          _peerConnection!.onRemoveTrack = _onRemoveTrack;
          _localStream!.getTracks().forEach((track) {
            _peerConnection!.addTrack(track, _localStream!);
          });
          break;
      }
      print("Peer Connection has been created");
    } catch (e) {
      print(e.toString());
    }
  }

  void _sendOffer(String sdp) async {
    var session = parse(sdp);
    String offerSdp = json.encode(session);

    _publishMessage(anotherMobile, WebRTC_Method.OFFER.index, offerSdp);
    print("OFFER has been sent to: $anotherMobile");
  }

  _createOffer() async {
    try {
      var description =
          await _peerConnection!.createOffer(offerSdpConstraints);
      print("Offer has been created");

      _peerConnection!.setLocalDescription(description);
      print("Local Description has been set");

      return description.sdp.toString();
    } catch (e) {
      print("Error in create offer: " + e.toString());
    }
  }

  _setRemoteDescription(String sdpString) async {
    RTCSessionDescription description =
        RTCSessionDescription(sdpString, _inCalling ? 'answer' : 'offer');
    await _peerConnection!.setRemoteDescription(description);
    print("Remote Description has been set.");
  }

  _createAnswer() async {
    var description =
        await _peerConnection!.createAnswer(offerSdpConstraints);
    print("Answer Description has been created.");

    _peerConnection!.setLocalDescription(description);
    print("Local Description has been set for ANWSER");

    return description.sdp.toString();
  }

  _sendAnswer(String sdp) async {
    var session = parse(sdp.toString());
    String answerSdp = json.encode(session);

    _publishMessage(anotherMobile, WebRTC_Method.ANSWER.index, answerSdp);
    print("ANSWER message has been sent to: $anotherMobile");
  }

  void _sendIceCandidate(String iceCandidate) async {
    _publishMessage(
        anotherMobile, WebRTC_Method.ICE_CANDIDATES.index, iceCandidate);
    print("ICE Candidates have been sent.: $anotherMobile");
  }

  void _addCandidate(Map<String, dynamic> candidate) async {
    dynamic rtcIcecandidate = RTCIceCandidate(candidate['candidate'],
        candidate['sdpMid'], candidate['sdpMlineIndex']);
    await _peerConnection!.addCandidate(rtcIcecandidate);
    print("ICE CANDIDATES have been added.");
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
        sdp = write(receivedMessage['Body'], null);
        _receiveCall(sdp);
      }
      if (receivedMessage['Type'] == WebRTC_Method.ANSWER.index) {
        print("ANSWER Message has been Received");
        sdp = write(receivedMessage['Body'], null);
        _setRemoteDescription(sdp);
      }
     
      if (receivedMessage['Type'] == WebRTC_Method.ICE_CANDIDATES.index) {
        print("ICE CANDIDATE Message has been Received");
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
    prepareMqttClient();
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

  void _sendDtmf() async {
    var dtmfSender =
        _peerConnection?.createDtmfSender(_localStream!.getAudioTracks()[0]);
    await dtmfSender?.insertDTMF('123#');
  }

  @override
  Widget build(BuildContext context) {
    var widgets = <Widget>[
      Expanded(
        child: RTCVideoView(_localRenderer, mirror: true),
      ),
      Expanded(
        child: RTCVideoView(_remoteRenderer),
      )
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: _inCalling
            ? <Widget>[
                IconButton(
                  icon: Icon(Icons.keyboard),
                  onPressed: _sendDtmf,
                ),
              ]
            : null,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              decoration: BoxDecoration(color: Colors.black54),
              child: orientation == Orientation.portrait
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: widgets)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: widgets),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inCalling ? _hangUp : _makeCall,
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
