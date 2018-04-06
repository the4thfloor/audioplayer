import 'dart:async';

import 'package:audioplayers/audioplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef void OnError(Exception exception);

const kUrl1 = "http://www.rxlabz.com/labz/audio.mp3";
const kUrl2 = "http://www.rxlabz.com/labz/audio2.mp3";

void main() {
  runApp(new MaterialApp(home: new Scaffold(body: new AudioApp())));
}

enum PlayerState { stopped, playing, paused }

class AudioApp extends StatefulWidget {
  @override
  _AudioAppState createState() => new _AudioAppState();
}

class _AudioAppState extends State<AudioApp> {
  AudioPlayer audioPlayer;

  PlayerState playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    initAudioPlayer();
  }

  void initAudioPlayer() {
    audioPlayer = new AudioPlayer();

    audioPlayer.setDurationHandler((d) => setState(() {
          print('_AudioAppState.setDurationHandler => d ${d}');
        }));

    audioPlayer.setPositionHandler((p) => setState(() {
          print('_AudioAppState.setPositionHandler => p ${p}');
        }));

    audioPlayer.setErrorHandler((msg) {
      print('audioPlayer error : $msg');
      setState(() {
        playerState = PlayerState.stopped;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return new Center(
      child: new Column(
        children: [
          new _PlayerUiWidget(url: kUrl1),
          new _PlayerUiWidget(url: kUrl2),
        ],
      ),
    );
  }
}

class _PlayerUiWidget extends StatefulWidget {
  final String url;

  _PlayerUiWidget({@required this.url});

  @override
  State<StatefulWidget> createState() {
    return new _PlayerUiWidgetState(url: url);
  }
}

class _PlayerUiWidgetState extends State<_PlayerUiWidget> {
  String url;
  AudioPlayer _audioPlayer;
  Duration _duration;
  Duration _position;

  PlayerState _playerState = PlayerState.stopped;

  get _isPlaying => _playerState == PlayerState.playing;
  get _isPaused => _playerState == PlayerState.paused;
  get _durationText => _duration?.toString()?.split('.')?.first ?? '';
  get _positionText => _position?.toString()?.split('.')?.first ?? '';

  _PlayerUiWidgetState({@required this.url});

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
  }

  @override
  void dispose() {
    super.dispose();
    _audioPlayer.stop();
  }

  @override
  Widget build(BuildContext context) {
    return new Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        new Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            new IconButton(
                onPressed: _isPlaying ? null : () => _play(),
                iconSize: 64.0,
                icon: new Icon(Icons.play_arrow),
                color: Colors.cyan),
            new IconButton(
                onPressed: _isPlaying ? () => _pause() : null,
                iconSize: 64.0,
                icon: new Icon(Icons.pause),
                color: Colors.cyan),
            new IconButton(
                onPressed: _isPlaying || _isPaused ? () => _stop() : null,
                iconSize: 64.0,
                icon: new Icon(Icons.stop),
                color: Colors.cyan),
          ],
        ),
        new Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            new Padding(
              padding: new EdgeInsets.all(12.0),
              child: new Stack(
                children: [
                  new CircularProgressIndicator(
                    value: 1.0,
                    valueColor: new AlwaysStoppedAnimation(Colors.grey[300]),
                  ),
                  new CircularProgressIndicator(
                    value: _position != null && _position.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0.0,
                    valueColor: new AlwaysStoppedAnimation(Colors.cyan),
                  ),
                ],
              ),
            ),
            new Text(
              _position != null
                  ? "${_positionText ?? ''} / ${_durationText ?? ''}"
                  : _duration != null ? _durationText : '',
              style: new TextStyle(fontSize: 24.0),
            ),
          ],
        ),
      ],
    );
  }

  void _initAudioPlayer() {
    _audioPlayer = new AudioPlayer();

    _audioPlayer.setDurationHandler((d) => setState(() {
          _duration = d;
        }));

    _audioPlayer.setPositionHandler((p) => setState(() {
          _position = p;
        }));

    _audioPlayer.setCompletionHandler(() {
      _onComplete();
      setState(() {
        _position = _duration;
      });
    });

    _audioPlayer.setErrorHandler((msg) {
      print('audioPlayer error : $msg');
      setState(() {
        _playerState = PlayerState.stopped;
        _duration = new Duration(seconds: 0);
        _position = new Duration(seconds: 0);
      });
    });
  }

  Future _play() async {
    final result = await _audioPlayer.play(url);
    if (result == 1) setState(() => _playerState = PlayerState.playing);
  }

  Future _pause() async {
    final result = await _audioPlayer.pause();
    if (result == 1) setState(() => _playerState = PlayerState.paused);
  }

  Future _stop() async {
    final result = await _audioPlayer.stop();
    if (result == 1)
      setState(() {
        _playerState = PlayerState.stopped;
        _position = new Duration();
      });
  }

  void _onComplete() {
    setState(() => _playerState = PlayerState.stopped);
  }
}
