import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

class Classicalscreen extends StatefulWidget {
  const Classicalscreen({super.key});

  @override
  _ClassicalScreenState createState() => _ClassicalScreenState();
}

class _ClassicalScreenState extends State<Classicalscreen> {
  // Flutter Blue Classic Plugin Instance
  final _flutterBlueClassicPlugin = FlutterBlueClassic(usesFineLocation: true);

  // Device Lists
  List<BluetoothDevice>? _pairedDevices = []; // Paired Devices
  List<BluetoothDevice> _discoveredDevices = []; // Unpaired Devices

  // State Variables
  bool _isScanning = false;
  String status = 'Press scan to start'; // Connection Status
  bool isCurrentDevicePaired = false;
  bool isCurrentDeviceConnected = false;
  String inputData = "no data";

  // Connection and Timer
  BluetoothConnection? _classicalConnection;
  Timer? _reconnectTimer;
  bool _isConnecting = false;

  // Device Address
  String? _currentDeviceAddress;

  @override
  void initState() {
    super.initState();
    getPairedDevices();
  }

  // Paired Devices
  Future<void> getPairedDevices() async {
    await checkAndRequestPermissions();
    List<BluetoothDevice>? devices =
        await _flutterBlueClassicPlugin.bondedDevices;
    setState(() {
      _pairedDevices = devices;
    });
  }

  void deviceTapHandler(BluetoothDevice device) async {
    if (await isDevicePaired(device.address)) {
      setState(() {
        status = 'Device is paired';
      });

      bool connectionStatus = await connectNow(device);

      //This will run if the device is paired but not connected
      if (connectionStatus) {
        setState(() {
          status = 'Device connected Succesfully';
        });
        print('Device connected succesfully');
        sendData('Hello');
      } else if (connectionStatus == false) {
        setState(() {
          status = 'Device already connected';
        });
      }
    } else {
      setState(() {
        status = 'Device is not paired, attempting to pair...';
      });
      bool paired = await pairNow(device.address);
      if (paired) {
        setState(() {
          isCurrentDevicePaired = true;
          status = 'Paired successfully and connected autmatically';
          status = 'Device paired';
        });
        sendData('Hello');
      } else {
        print("not able to pair");
        setState(() {
          status = 'not able to pair';
        });
      }
    }
  }

  Future<bool> connectNow(BluetoothDevice device) async {
    try {
      _classicalConnection =
          await _flutterBlueClassicPlugin.connect(device.address);
      print("Actual conection : ${_classicalConnection?.isConnected}");
      if (_classicalConnection?.isConnected == true) {
        _classicalConnection!.input!.listen((Uint8List data) {
          setState(() {
            inputData = ascii.decode(data);
          });
          print('Data incoming: $inputData');
        });
        return true;
      }
      return false; // Return false if connection is null or not connected.
    } catch (e) {
      // Handle any errors that might occur during the connection attempt.
      print('Error connecting to device: $e');
      setState(() {
        status = 'error connection: $e';
      });
      return false;
    }
  }

  // Pairing
  Future<bool> pairNow(String macAddress) async {
    try {
      setState(() {
        status = 'Attempting to pair with device: $macAddress';
      });

      bool isPairingStarted =
          await _flutterBlueClassicPlugin.bondDevice(macAddress);

      if (isPairingStarted) {
        setState(() {
          status = 'Pairing Started';
        });
      } else {
        throw ('Pairing was not able to start');
      }

      await Future.delayed(Duration(seconds: 5));
      await getPairedDevices();

      if (await isDevicePaired(macAddress)) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      setState(() {
        status = e.toString();
      });
      return false;
    }
  }

  Future<bool> isDevicePaired(String macAddress) async {
    await getPairedDevices();
    if (_pairedDevices != null) {
      return _pairedDevices!
          .any((device) => (device.address).toString() == macAddress);
    }
    return false;
  }

  // Permissions
  Future<void> checkAndRequestPermissions() async {
    if (await Permission.bluetoothScan.isGranted == false) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isGranted == false) {
      await Permission.bluetoothConnect.request();
    }
    if (await Permission.bluetooth.isGranted == false) {
      await Permission.bluetooth.request();
    }
    if (await Permission.location.isGranted == false) {
      await Permission.location.request();
    }

    if (await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted &&
        await Permission.location.isGranted) {
      debugPrint("All required permissions granted.");
    } else {
      debugPrint("Some permissions are missing!");
    }
  }

  Future<void> _scan() async {
    if (_isScanning) {
      stopPressHandler();
    } else {
      _flutterBlueClassicPlugin.startScan();
      _flutterBlueClassicPlugin.scanResults.listen((device) {
        setState(() {
          _discoveredDevices.add(device);
        });
      });
      setState(() {
        _isScanning = true;
      });
      await Future.delayed(Duration(seconds: 10));
      _flutterBlueClassicPlugin.stopScan();
      setState(() {
        status = 'Scanning completed';
      });
    }
  }

  // Start Scan
  void scanPressHandler() async {
    setState(() {
      status = 'Scanning...';
    });
    _scan();
  }

  //Stop Scan
  void stopPressHandler() {
    _flutterBlueClassicPlugin.stopScan();
    print('stop button pressed');
    dispose();
    setState(() {
      _isScanning = false;
      _discoveredDevices = [];
      status = 'Press Scan to start';
    });
  }

  Future<void> sendData(String data) async {
    if (_classicalConnection != null && _classicalConnection!.isConnected) {
      try {
        // Convert the string data to bytes
        List<int> bytes = utf8.encode(data);

        // Send the bytes to the connected device
        _classicalConnection!.output.add(Uint8List.fromList(bytes));
        await _classicalConnection!.output.allSent;

        setState(() {
          status = 'Data sent successfully';
        });
        print('Data sent: $data');
      } catch (e) {
        setState(() {
          status = 'Error sending data: $e';
        });
        print('Error sending data: $e');
      }
    } else {
      setState(() {
        status = 'No device connected';
      });
      print('No device connected');
    }
  }

  // UI Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Device status : $status',
            style: TextStyle(fontSize: 20, color: Colors.blue),
          ),
          SizedBox(height: 20),
          ElevatedButton(onPressed: scanPressHandler, child: Text('Scan')),
          SizedBox(height: 20),
          ElevatedButton(onPressed: stopPressHandler, child: Text('Stop')),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => sendData('Hello'),
            child: Text('Send Data'),
          ),
          Container(
            height: MediaQuery.of(context).size.height * 0.5,
            width: MediaQuery.of(context).size.width * 0.95,
            decoration: BoxDecoration(color: Colors.lightBlue),
            child: SingleChildScrollView(
              child: Row(
                children: [
                  // Discovered Devices
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Discovered Devices"),
                        for (var device in _discoveredDevices)
                          GestureDetector(
                            onTap: () {
                              deviceTapHandler(device);
                            },
                            child: Container(
                              height: MediaQuery.of(context).size.height * 0.06,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.pink)),
                              child: Column(
                                children: [
                                  Text(device.name ?? device.address),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Paired Devices
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Paired Devices"),
                        if (_pairedDevices != null)
                          for (var device in _pairedDevices!)
                            Container(
                              height: MediaQuery.of(context).size.height * 0.04,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.pink)),
                              child: Text(device.name ?? device.address),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
