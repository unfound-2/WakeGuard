import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_ble_alarm/core/firebase/app_firebase.dart';
import 'package:smart_ble_alarm/core/observability/crash_reporting_service.dart';

import 'app/app_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartAlarmBootstrap());
  unawaited(_initializeDeferredServices());
}

Future<void> _initializeDeferredServices() async {
  try {
    await AppFirebase.ensureInitialized();
    await CrashReportingService.initialize();
  } catch (error, stackTrace) {
    debugPrint('Deferred service startup failed: $error\n$stackTrace');
  }
}
