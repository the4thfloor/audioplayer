package bz.rxla.audioplayer;

import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Handler;
import android.util.Pair;

import java.io.IOException;
import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * AudioplayerPlugin
 */
public class AudioplayerPlugin implements MethodCallHandler, MediaPlayer.OnPreparedListener, MediaPlayer.OnCompletionListener, MediaPlayer.OnSeekCompleteListener {

    private final MethodChannel                          channel;
    private final Map<String, Pair<String, MediaPlayer>> mediaPlayers = new HashMap<>();
    private final Handler                                handler      = new Handler();
    private Runnable                                     positionUpdates;


    public static void registerWith(final Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "bz.rxla.flutter/audio");
        channel.setMethodCallHandler(new AudioplayerPlugin(channel));
    }

    private AudioplayerPlugin(final MethodChannel channel) {
        this.channel = channel;
        this.channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(final MethodCall call, final MethodChannel.Result response) {
        final String playerId = call.argument("playerId");
        switch (call.method) {
            case "play":
                final String url = call.argument("url");
                final double volume = call.argument("volume");
                try {
                    play(playerId, url, (float) volume);
                    response.success(1);
                } catch (IOException e) {
                    e.printStackTrace();
                    response.error("IOException", e.getMessage(), e);
                }
                break;
            case "pause":
                pause(playerId);
                response.success(1);
                break;
            case "stop":
                stop(playerId);
                response.success(1);
                break;
            case "seek":
                double position = call.argument("position");
                seek(playerId, position);
                response.success(1);
                break;
            case "volume":
                double newVolume = call.argument("volume");
                volume(playerId, (float) newVolume);
                response.success(1);
                break;
            default:
                response.notImplemented();
                break;
        }
    }

    @Override
    public void onPrepared(final MediaPlayer mediaPlayer) {
        mediaPlayer.start();
        sendPositionUpdates();
    }

    @Override
    public void onCompletion(final MediaPlayer mediaPlayer) {
        mediaPlayer.stop();
        mediaPlayer.reset();
        mediaPlayer.release();
        removePlayer(mediaPlayer);
    }

    @Override
    public void onSeekComplete(final MediaPlayer mp) {
        for (final Map.Entry<String, Pair<String, MediaPlayer>> next : mediaPlayers.entrySet()) {
            final MediaPlayer mediaPlayer = next.getValue().second;
            if (mediaPlayer != mp) {
                continue;
            }
            final String playerId = next.getKey();
            final int time = mediaPlayer.getCurrentPosition();
            channel.invokeMethod("audio.onCurrentPosition", buildArguments(playerId, time));
            channel.invokeMethod("audio.seekToFinished", buildArguments(playerId, true));
        }
    }

    private void play(final String playerId, final String url, final float volume) throws IOException {

        Pair<String, MediaPlayer> pair = mediaPlayers.get(playerId);

        if (pair != null && pair.first.equals(url)) {
            pair.second.start();
            return;
        }

        if (pair != null && pair.second != null) {
            pair.second.release();
        }

        final MediaPlayer mediaPlayer = new MediaPlayer();
        mediaPlayers.put(playerId, Pair.create(url, mediaPlayer));
        mediaPlayer.setOnPreparedListener(this);
        mediaPlayer.setOnCompletionListener(this);
        mediaPlayer.setOnSeekCompleteListener(this);
        mediaPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
        mediaPlayer.setDataSource(url);
        mediaPlayer.setVolume(volume, volume);
        mediaPlayer.prepareAsync();
    }

    private void pause(final String playerId) {
        Pair<String, MediaPlayer> pair = mediaPlayers.get(playerId);
        if (pair != null && pair.second != null) {
            pair.second.pause();
        }
    }

    private void seek(final String playerId, final double position) {
        channel.invokeMethod("audio.seekToFinished", buildArguments(playerId, false));
        Pair<String, MediaPlayer> pair = mediaPlayers.get(playerId);
        if (pair != null && pair.second != null) {
            pair.second.seekTo((int) (position * 1000));
        }
    }

    private void stop(final String playerId) {
        Pair<String, MediaPlayer> pair = mediaPlayers.get(playerId);
        if (pair != null && pair.second != null) {
            onCompletion(pair.second);
        }
    }

    private void volume(final String playerId, final float volume) {
        Pair<String, MediaPlayer> pair = mediaPlayers.get(playerId);
        if (pair != null && pair.second != null) {
            pair.second.setVolume(volume, volume);
        }
    }

    private void removePlayer(final MediaPlayer mediaPlayer) {
        final Iterator<Map.Entry<String, Pair<String, MediaPlayer>>> iterator = mediaPlayers.entrySet()
                                                                                            .iterator();
        while (iterator.hasNext()) {
            final Map.Entry<String, Pair<String, MediaPlayer>> next = iterator.next();
            if (next.getValue().second == mediaPlayer) {
                iterator.remove();
                channel.invokeMethod("audio.onComplete", buildArguments(next.getKey(), true));
                break;
            }
        }
    }

    private void sendPositionUpdates() {
        if (positionUpdates != null) {
            return;
        }
        positionUpdates = new UpdateCallback(mediaPlayers, channel, handler, this);
        handler.post(positionUpdates);
    }

    void stopPositionUpdates() {
        positionUpdates = null;
        handler.removeCallbacksAndMessages(null);
    }

    static Map<String, Object> buildArguments(String playerId, Object value) {
        Map<String, Object> result = new HashMap<>();
        result.put("playerId", playerId);
        result.put("value", value);
        return result;
    }

    private static final class UpdateCallback implements Runnable {

        private final WeakReference<Map<String, Pair<String, MediaPlayer>>> _mediaPlayers;
        private final WeakReference<MethodChannel>                          _channel;
        private final WeakReference<Handler>                                _handler;
        private final WeakReference<AudioplayerPlugin>                      _audioplayerPlugin;

        UpdateCallback(final Map<String, Pair<String, MediaPlayer>> mediaPlayers,
                       final MethodChannel channel,
                       final Handler handler,
                       final AudioplayerPlugin audioplayerPlugin) {
            _mediaPlayers = new WeakReference<>(mediaPlayers);
            _channel = new WeakReference<>(channel);
            _handler = new WeakReference<>(handler);
            _audioplayerPlugin = new WeakReference<>(audioplayerPlugin);
        }

        @Override
        public void run() {

            final Map<String, Pair<String, MediaPlayer>> mediaPlayers = _mediaPlayers.get();
            final MethodChannel channel = _channel.get();
            final Handler handler = _handler.get();
            final AudioplayerPlugin audioplayerPlugin = _audioplayerPlugin.get();

            if (mediaPlayers == null || channel == null || handler == null || audioplayerPlugin == null) {
                return;
            }

            if (mediaPlayers.isEmpty()) {
                audioplayerPlugin.stopPositionUpdates();
                return;
            }

            for (final Map.Entry<String, Pair<String, MediaPlayer>> next : mediaPlayers.entrySet()) {
                final MediaPlayer mediaPlayer = next.getValue().second;
                if (!mediaPlayer.isPlaying()) {
                    continue;
                }
                final String key = next.getKey();
                final int duration = mediaPlayer.getDuration();
                final int time = mediaPlayer.getCurrentPosition();
                channel.invokeMethod("audio.onDuration", buildArguments(key, duration));
                channel.invokeMethod("audio.onCurrentPosition", buildArguments(key, time));
            }
            handler.postDelayed(this, 200);
        }
    }
}
