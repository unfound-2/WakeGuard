import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../domain/repositories/ble_repository.dart';
import 'ble_event.dart';
import 'ble_state.dart';

class BleConnectionBloc extends Bloc<BleEvent, BleState> {
  final BleRepository bleRepository;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  BluetoothDevice? _connectedDevice;

  BleConnectionBloc({required this.bleRepository}) : super(BleDisconnected()) {
    on<StartScanEvent>(_onStartScan);
    on<StopScanEvent>(_onStopScan);
    on<DeviceFoundEvent>(_onDeviceFound);
    on<ConnectionStateChangedEvent>(_onConnectionStateChanged);
    on<ToggleSimulationEvent>(_onToggleSimulation);
    on<AutoConnectEvent>(_onAutoConnect);
  }

  void _onStartScan(StartScanEvent event, Emitter<BleState> emit) async {
    emit(BleScanning());
    
    _scanSubscription?.cancel();
    _scanSubscription = bleRepository.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName.toLowerCase().contains("hm-10") || 
            r.device.platformName.toLowerCase().contains("hmsoft")) {
          add(DeviceFoundEvent(r.device));
          break;
        }
      }
    });

    try {
      await bleRepository.startScan();
    } catch (e) {
      emit(BleDisconnected());
    }
  }

  void _onStopScan(StopScanEvent event, Emitter<BleState> emit) async {
    await bleRepository.stopScan();
    if (state is BleScanning) {
      emit(BleDisconnected());
    }
  }

  void _onAutoConnect(AutoConnectEvent event, Emitter<BleState> emit) async {
    if (event.deviceId == 'simulated_device') {
      final device = BluetoothDevice.fromId('simulated_device');
      _connectedDevice = device;
      
      _connectionSubscription?.cancel();
      _connectionSubscription = bleRepository.connectionState(device).listen((connectionState) {
        add(ConnectionStateChangedEvent(connectionState));
      });

      try {
        await bleRepository.connectToDevice(device);
      } catch (e) {
        emit(BleDisconnected());
      }
      return;
    }

    emit(BleConnecting());
    
    _scanSubscription?.cancel();
    _scanSubscription = bleRepository.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.remoteId.str == event.deviceId) {
          add(DeviceFoundEvent(r.device));
          break;
        }
      }
    });

    try {
      await bleRepository.startScan();
    } catch (e) {
      emit(BleDisconnected());
    }
  }

  void _onDeviceFound(DeviceFoundEvent event, Emitter<BleState> emit) async {
    await bleRepository.stopScan();
    emit(BleConnecting());
    
    _connectedDevice = event.device;
    _connectionSubscription?.cancel();
    _connectionSubscription = bleRepository.connectionState(event.device).listen((connectionState) {
      add(ConnectionStateChangedEvent(connectionState));
    });

    try {
      await bleRepository.connectToDevice(event.device);
    } catch (e) {
      emit(BleDisconnected());
    }
  }

  void _onConnectionStateChanged(ConnectionStateChangedEvent event, Emitter<BleState> emit) {
    if (event.state == BluetoothConnectionState.connected && _connectedDevice != null) {
      emit(BleConnected(_connectedDevice!));
    } else if (event.state == BluetoothConnectionState.disconnected) {
      _connectedDevice = null;
      emit(BleDisconnected());
    }
  }

  void _onToggleSimulation(ToggleSimulationEvent event, Emitter<BleState> emit) {
    if (state is BleConnected && _connectedDevice?.remoteId.str == 'simulated_device') {
      bleRepository.disconnectFromDevice(_connectedDevice!);
    } else {
      add(const AutoConnectEvent('simulated_device'));
    }
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    return super.close();
  }
}
