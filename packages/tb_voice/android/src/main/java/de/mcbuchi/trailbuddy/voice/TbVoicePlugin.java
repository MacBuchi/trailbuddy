package de.mcbuchi.trailbuddy.voice;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Ansagen übers Ohr (#525): Android TextToSpeech mit der Stimme des Geräts.
 * Kein Netz, kein neuer Host. Je Satz holt es den Audio-Fokus
 * „vorübergehend, darf leiser machen" — Musik wird leiser, sie stoppt nicht —
 * und gibt ihn nach dem Satz frei. Läuft in jeder Engine, auch in der des
 * Vordergrund-Dienstes; deshalb ein Plugin und kein Kanal in MainActivity.
 */
public class TbVoicePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    static final String CHANNEL = "de.mcbuchi.trailbuddy/voice";

    private MethodChannel channel;
    private Context context;
    private AudioManager audio;
    private TextToSpeech tts;
    private boolean ready = false;
    private boolean failed = false;
    private final List<Runnable> pending = new ArrayList<>();
    private int utterance = 0;
    private int speaking = 0;
    private AudioFocusRequest focusRequest;

    private final AudioAttributes attributes = new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build();

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
        tts = null;
        ready = false;
        pending.clear();
        abandonFocus();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("speak".equals(call.method)) {
            final String text = call.argument("text");
            final String language = call.argument("language");
            if (text == null || text.trim().isEmpty()) {
                result.success(false);
                return;
            }
            speak(text, language);
            result.success(true);
        } else {
            result.notImplemented();
        }
    }

    private void speak(final String text, final String language) {
        if (failed) return;
        final Runnable run = () -> say(text, language);
        if (ready) {
            run.run();
            return;
        }
        pending.add(run);
        if (tts != null) return;
        // Der Rückruf kommt auf dem Haupt-Thread, wie die Kanal-Aufrufe.
        tts = new TextToSpeech(context, status -> {
            if (status != TextToSpeech.SUCCESS) {
                failed = true;
                pending.clear();
                return;
            }
            ready = true;
            tts.setAudioAttributes(attributes);
            tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                @Override
                public void onStart(String id) {}

                @Override
                public void onDone(String id) {
                    finished();
                }

                @Override
                @SuppressWarnings("deprecation")
                public void onError(String id) {
                    finished();
                }

                @Override
                public void onError(String id, int code) {
                    finished();
                }
            });
            for (Runnable r : new ArrayList<>(pending)) r.run();
            pending.clear();
        });
    }

    private void say(String text, String language) {
        if (tts == null) return;
        if (language != null) {
            final Locale locale = Locale.forLanguageTag(language);
            if (tts.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) tts.setLanguage(locale);
        }
        requestFocus();
        synchronized (this) {
            speaking++;
        }
        final int result = tts.speak(text, TextToSpeech.QUEUE_ADD, null, "tb-" + (utterance++));
        if (result != TextToSpeech.SUCCESS) finished();
    }

    private void finished() {
        boolean idle;
        synchronized (this) {
            speaking = Math.max(0, speaking - 1);
            idle = speaking == 0;
        }
        if (idle) abandonFocus();
    }

    private void requestFocus() {
        if (audio == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest == null) {
                focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(attributes)
                        .build();
            }
            audio.requestAudioFocus(focusRequest);
        } else {
            requestFocusLegacy();
        }
    }

    @SuppressWarnings("deprecation")
    private void requestFocusLegacy() {
        audio.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK);
    }

    private void abandonFocus() {
        if (audio == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest != null) audio.abandonAudioFocusRequest(focusRequest);
        } else {
            abandonFocusLegacy();
        }
    }

    @SuppressWarnings("deprecation")
    private void abandonFocusLegacy() {
        audio.abandonAudioFocus(null);
    }
}
