import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketClient {
  String webSocketHost = "localhost";
  String websocketPort = "8080";
  String webSocketKey = "h3rixwse35kzcnrmdptw";
  String get webSocketUrl => "ws://$webSocketHost:$websocketPort/app/$webSocketKey";

  // ws://${apiClient.host}:$websocketPort/app/$webSocketKey

  late WebSocketChannel channel;

  WebSocketClient();

  void setWebSocketUrl(String host, String port) {
    webSocketHost = host;
    websocketPort = port;
  }

  /// Connects to the WebSocket at [channel] and returns [true] if
  /// successful.
  ///
  /// At the moment this function provides no additional guards,
  /// so it's recommended to handle any potential exceptions elsewhere.
  Future<bool> connect() async {
    channel = WebSocketChannel.connect(Uri.parse(webSocketUrl));

    try {
      await channel.ready;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Subscribes to a list of events, allowing the WebSocket to listen
  /// to any potential events sent on those channels.
  ///
  /// This should be formatted in a valid JSON that the WebSocketGateway
  /// accepts, such as:
  ///   {
  ///      "event": "pusher:subscribe",
  ///      "data": {"channel": "test-channel"},
  ///    };
  ///
  Future<void> subscribe(Map<String, dynamic> subscription) async {
    channel.sink.add(jsonEncode(subscription));
  }

  /// Listens to events in specific channels and pass it on to [onDataReceived].
  ///
  /// [onDataReceived] should accept a [String] which represents the channel
  /// name that the event is received in and a [List] containing the details
  /// regarding the received event.
  ///
  /// At the moment, this function offers no way to differentiate
  /// between the events emitted by different channels, so a unique event
  /// name for every channel is recommended.
  Future<void> listenTo(
    List<String> socketChannels,
    List<String> events,
    Function onDataReceived,
  ) async {
    channel.stream.listen(
      cancelOnError: true,
      (message) async {
        // Handle ping request from the server.
        if (message.toString().contains('ping')) {
          channel.sink.add(json.encode({"event": "pusher:pong"}));
        }

        // Parse data that we have received.
        final data = jsonDecode(message);
        if (socketChannels.contains(data['channel'])) {
          final eventData = jsonDecode(data['data']);

          // We explicitly want this specifically, so stream the data back.
          if (events.contains(eventData['message'])) {
            onDataReceived(data['channel'], eventData);
          }
        }
      },
      onDone: () {
        print('Connection closed.');
        return;
      },
      onError: (error) {
        print(error);
        return;
      },
    );
  }
}
