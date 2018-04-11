import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

typedef void TimeChangeHandler(Duration duration);
typedef void SeekToFinishedHandler(bool finished);
typedef void ErrorHandler(String message);

class AudioPlayer {
  static final MethodChannel _channel = const MethodChannel('bz.rxla.flutter/audio')
    ..setMethodCallHandler(platformCallHandler);
  static final uuid = new Uuid();
  static final players = new Map<String, AudioPlayer>();
  static var logEnabled = false;

  TimeChangeHandler durationHandler;
  TimeChangeHandler positionHandler;
  VoidCallback completionHandler;
  SeekToFinishedHandler seekToFinishedHandler;
  ErrorHandler errorHandler;
  String playerId;

  AudioPlayer() {
    playerId = uuid.v4();
    players[playerId] = this;
  }

  Future<int> play(String url, {bool isLocal: false, double volume: 1.0, bool loop: false}) async {
    final int state = await _channel.invokeMethod('play', {"playerId": playerId, "url": url, "isLocal": isLocal, 'volume': volume, 'loop': loop});
    return new Future.value(state);
  }

  Future<int> pause() async {
    final int state = await _channel.invokeMethod('pause', {"playerId": playerId});
    return new Future.value(state);
  }

  Future<int> stop() async {
    final int state = await _channel.invokeMethod('stop', {"playerId": playerId});
    return new Future.value(state);
  }

  Future<int> seek(double seconds) async {
    final int state = await _channel.invokeMethod('seek', {"playerId": playerId, "position": seconds});
    return new Future.value(state);
  }

  /// set audio volume from 0.0 (silent) to1.0 (max)
  Future<int> volume(double volume) async {
    final int state = await _channel.invokeMethod('volume', {"playerId": playerId, "volume": volume});
    return new Future.value(state);
  }

  void setDurationHandler(TimeChangeHandler handler) {
    durationHandler = handler;
  }

  void setPositionHandler(TimeChangeHandler handler) {
    positionHandler = handler;
  }

  void setCompletionHandler(VoidCallback callback) {
    completionHandler = callback;
  }

  void setSeekToFinishedHandler(SeekToFinishedHandler callback) {
    seekToFinishedHandler = callback;
  }

  void setErrorHandler(ErrorHandler handler) {
    errorHandler = handler;
  }

  static void log(String param) {
    if (logEnabled) {
      print(param);
    }
  }

  static Future platformCallHandler(MethodCall call) async {
    log("_platformCallHandler call ${call.method} ${call.arguments}");
    String playerId = (call.arguments as Map)['playerId'];
    AudioPlayer player = players[playerId];
    dynamic value = (call.arguments as Map)['value'];
    switch (call.method) {
      case "audio.onDuration":
        if (player.durationHandler != null) {
          player.durationHandler(new Duration(milliseconds: value));
        }
        break;
      case "audio.onCurrentPosition":
        if (player.positionHandler != null) {
          player.positionHandler(new Duration(milliseconds: value));
        }
        break;
      case "audio.onComplete":
        if (player.completionHandler != null) {
          player.completionHandler();
        }
        break;
      case "audio.seekToFinished":
        if (player.seekToFinishedHandler != null) {
          player.seekToFinishedHandler(value);
        }
        break;
      case "audio.onError":
        if (player.errorHandler != null) {
          player.errorHandler(value);
        }
        break;
      default:
        log('Unknowm method ${call.method} ');
    }
  }
}
