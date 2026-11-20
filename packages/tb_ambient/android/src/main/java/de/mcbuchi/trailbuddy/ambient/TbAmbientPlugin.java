package de.mcbuchi.trailbuddy.ambient;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.SystemClock;

import androidx.annotation.NonNull;

import java.util.Arrays;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

/**
 * Licht und Nähe für die Sensor-Rohdaten (#491): „dunkel und nah" spricht
 * für die Tasche — ein optionales Merkmal, das nur zählt, wenn das Gerät den
 * Sensor hat und er geliefert hat. Keine Berechtigung. Fehlt der Sensor,
 * endet der Strom sofort ohne Wert (kein Fehler).
 *
 * Je Wert eine Liste {Zeit in µs seit 1970, Werte …} — dieselbe Zeit wie
 * `sensors_plus`: Systemstart + Zeitstempel des Sensors, nicht die Ankunft.
 * Licht: {t, lux}; Nähe: {t, Abstand cm, größter Abstand cm} — viele Geräte
 * melden nur 0 oder den größten Abstand.
 *
 * Läuft in jeder Engine, auch in der des Vordergrund-Dienstes; deshalb ein
 * Plugin und kein Kanal in MainActivity.
 */
public class TbAmbientPlugin implements FlutterPlugin {
    static final String LIGHT_CHANNEL = "de.mcbuchi.trailbuddy/ambient_light";
    static final String PROXIMITY_CHANNEL = "de.mcbuchi.trailbuddy/ambient_proximity";

    private EventChannel light;
    private EventChannel proximity;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        final SensorManager manager = (SensorManager) binding.getApplicationContext()
                .getSystemService(Context.SENSOR_SERVICE);
        light = new EventChannel(binding.getBinaryMessenger(), LIGHT_CHANNEL);
        light.setStreamHandler(new Handler(manager, Sensor.TYPE_LIGHT));
        proximity = new EventChannel(binding.getBinaryMessenger(), PROXIMITY_CHANNEL);
        proximity.setStreamHandler(new Handler(manager, Sensor.TYPE_PROXIMITY));
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (light != null) light.setStreamHandler(null);
        if (proximity != null) proximity.setStreamHandler(null);
        light = null;
        proximity = null;
    }

    static final class Handler implements EventChannel.StreamHandler, SensorEventListener {
        private final SensorManager manager;
        private final int type;
        private EventChannel.EventSink sink;
        private long bootUs;
        private double maxRange;

        Handler(SensorManager manager, int type) {
            this.manager = manager;
            this.type = type;
        }

        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            final Sensor sensor = manager == null ? null : manager.getDefaultSensor(type);
            if (sensor == null) {
                events.endOfStream();
                return;
            }
            sink = events;
            maxRange = sensor.getMaximumRange();
            bootUs = System.currentTimeMillis() * 1000L - SystemClock.elapsedRealtimeNanos() / 1000L;
            manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL);
        }

        @Override
        public void onCancel(Object arguments) {
            if (manager != null) manager.unregisterListener(this);
            sink = null;
        }

        @Override
        public void onSensorChanged(SensorEvent event) {
            if (sink == null || event.values.length == 0) return;
            final double t = (double) (bootUs + event.timestamp / 1000L);
            final List<Double> values = type == Sensor.TYPE_PROXIMITY
                    ? Arrays.asList(t, (double) event.values[0], maxRange)
                    : Arrays.asList(t, (double) event.values[0]);
            sink.success(values);
        }

        @Override
        public void onAccuracyChanged(Sensor sensor, int accuracy) {}
    }
}
