// ignore_for_file: prefer_initializing_formals

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ble_alarm/core/firebase/app_firebase.dart';
import 'package:smart_ble_alarm/core/observability/crash_reporting_service.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';

class AlarmCloudSyncService {
  // Keep public constructor names friendly while assigning private lazy handles.
  AlarmCloudSyncService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth,
      _firestore = firestore;

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  Future<List<Alarm>> restoreIfLocalEmpty(List<Alarm> localAlarms) async {
    if (localAlarms.isNotEmpty) return localAlarms;
    // restoreBackups now rethrows genuine Firestore errors; this best-effort
    // caller keeps its original "fall back to local" behaviour on failure.
    try {
      return await restoreBackups(fallback: localAlarms);
    } catch (_) {
      return localAlarms;
    }
  }

  Future<List<Alarm>> restoreBackups({List<Alarm> fallback = const []}) async {
    final handles = await _handles();
    // Not signed in / Firebase not ready: there is nothing to read, so hand
    // back the fallback rather than treating this as an error.
    if (handles == null) return fallback;

    try {
      final snapshot = await handles.firestore
          .collection('users')
          .doc(handles.user.uid)
          .collection('alarmBackups')
          .orderBy('id')
          .get();

      // A genuinely empty collection returns an empty list (distinct from an
      // error) so callers can tell "no backups" from "read failed".
      return snapshot.docs
          .map((doc) => doc.data()['alarm'])
          .whereType<Map<String, dynamic>>()
          .map(Alarm.fromJson)
          .toList(growable: false);
    } catch (error, stackTrace) {
      // Record then RETHROW: a real Firestore failure must not masquerade as
      // "no backups", or a sign-in read failure would let callers wipe the
      // cloud. Callers distinguish empty-vs-error by catching this.
      await CrashReportingService.recordError(
        error,
        stackTrace,
        reason: 'Alarm backup restore failed',
      );
      rethrow;
    }
  }

  Future<void> syncAlarms(List<Alarm> alarms) async {
    final handles = await _handles();
    if (handles == null) return;

    try {
      final userRef = handles.firestore
          .collection('users')
          .doc(handles.user.uid);
      final batch = handles.firestore.batch();
      final backupRef = userRef.collection('alarmBackups');

      final existing = await backupRef.get();
      final currentIds = alarms.map((alarm) => '${alarm.id}').toSet();
      for (final doc in existing.docs) {
        if (!currentIds.contains(doc.id)) {
          batch.delete(doc.reference);
        }
      }

      for (final alarm in alarms) {
        batch.set(backupRef.doc('${alarm.id}'), {
          'id': alarm.id,
          'alarm': alarm.toJson(),
          'active': alarm.isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      batch.set(userRef, {
        'alarmBackupCount': alarms.length,
        'activeAlarmBackupCount': alarms
            .where((alarm) => alarm.isActive)
            .length,
        'alarmsBackedUpAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmCloudSyncService.syncAlarms failed: $error\n$stackTrace',
      );
      await CrashReportingService.recordError(
        error,
        stackTrace,
        reason: 'Alarm backup sync failed',
      );
    }
  }

  Future<_FirebaseHandles?> _handles() async {
    final firebaseReady = await AppFirebase.ensureInitialized();
    if (!firebaseReady) return null;
    _auth ??= FirebaseAuth.instance;
    _firestore ??= FirebaseFirestore.instance;
    final user = _auth!.currentUser;
    if (user == null) return null;
    return _FirebaseHandles(user: user, firestore: _firestore!);
  }
}

class _FirebaseHandles {
  final User user;
  final FirebaseFirestore firestore;

  const _FirebaseHandles({required this.user, required this.firestore});
}
