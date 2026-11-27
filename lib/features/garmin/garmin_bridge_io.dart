import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/errors.dart';
import 'garmin_bridge.dart';
import '../../core/platform_support.dart';

/// Der Name steht auch in `GarminBridge.kt` und `GarminBridge.swift`;
/// `android_manifest_test` und `ios_support_test` halten sie zusammen.
const kGarminChannel = 'de.mcbuchi.trailbuddy/garmin';

GarminBridge createGarminBridge() => _ChannelGarminBridge();

class _ChannelGarminBridge implements GarminBridge {
  static const _channel = MethodChannel(kGarminChannel);

  final _messages = StreamController<Object?>.broadcast();
  final _connected = StreamController<void>.broadcast();
  final _picked = StreamController<void>.broadcast();
  bool _listening = false;

  @override
  bool get supported => hasAndroidChannels || hasIosChannels;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'message') _messages.add(call.arguments);
      if (call.method == 'device' && call.arguments == 'CONNECTED') {
        _connected.add(null);
      }
      if (call.method == 'device' && call.arguments == 'PICKED') {
        _picked.add(null);
      }
    });
  }

  @override
  Future<WatchStatus> status() async {
    if (!supported) return WatchStatus.none;
    _listen();
    try {
      final raw = await _channel.invokeMethod<Object?>('status', {
        'appId': kWatchAppId,
        'tethered': kGarminTethered,
      });
      return WatchStatus.fromChannel(raw);
    } catch (e, s) {
      logError('Garmin-Status', e, s);
      return WatchStatus.none;
    }
  }

  @override
  Future<WatchSendResult> send(List<Map<String, Object>> messages) async {
    if (!supported) return const WatchSendResult('NOT_SUPPORTED', 0);
    try {
      final raw = await _channel.invokeMethod<Object?>('send', {
        'messages': messages,
      });
      return WatchSendResult.fromChannel(raw);
    } catch (e, s) {
      logError('Route an die Uhr', e, s);
      return const WatchSendResult('FAILURE_UNKNOWN', 0);
    }
  }

  @override
  Future<WatchOpen> open() async {
    if (!supported) return WatchOpen.unknown;
    try {
      return WatchOpen.fromChannel(
        await _channel.invokeMethod<Object?>('open'),
      );
    } catch (e, s) {
      logError('Uhr-App öffnen', e, s);
      return WatchOpen.unknown;
    }
  }

  @override
  Future<bool> listen() async {
    if (!supported) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('listen', {
            'appId': kWatchAppId,
            'tethered': kGarminTethered,
          }) ??
          false;
    } catch (e, s) {
      logError('Auf die Uhr lauschen', e, s);
      return false;
    }
  }

  @override
  Future<bool> pick() async {
    // Auf Android sieht das SDK die Uhr von selbst.
    if (!hasIosChannels) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('pick') ?? false;
    } catch (e, s) {
      logError('Uhr wählen', e, s);
      return false;
    }
  }

  @override
  Stream<void> get picked => _picked.stream;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Stream<void> get connected => _connected.stream;
}
