import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

class Classicalscreen extends StatefulWidget {
  const Classicalscreen({super.key});

  @override
  _ClassicalScreenState createState() => _ClassicalScreenState();
}

class _ClassicalScreenState extends State<Classicalscreen> {
  final _flutterBlueClassicPlugin = FlutterBlueClassic(usesFineLocation: true);
  List<BluetoothDevice>? _pairedDevices = []; //Paired Devices
  List<BluetoothDevice> _discoveredDevices = []; //Unpaired Devices
  bool _isScanning = false;
  String status = 'Press scan to start'; //Connection Status
  bool isCurrentDevicePaired = false;
  bool isCurrentDeviceConnected = false;

  BluetoothConnection? _currentConnection;
  Timer? _reconnectTimer;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    // Add any initialization code here
    getPairedDevices();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }
    if (await Permission.locationAlways.isDenied) {
      await Permission.locationAlways.request();
    }
  }

  Future isDevicePaired(String macAddress) async {
    // Refresh the paired devices list
    await getPairedDevices();
    if (_pairedDevices != null) {
      return _pairedDevices!
          .any((device) => (device.address).toString() == macAddress);
    }
    return false;
  }

  //This will scan for devices available nearby
  void scanPressHandler() async {
    setState(() {
      status = 'Scanning...';
    });
    _scan();
  }

  void stopPressHandler() {
    _flutterBlueClassicPlugin.stopScan();
    setState(() {
      _isScanning = false;
      _discoveredDevices = [];
      status = 'Press Scan to start';
    });
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
      await Future.delayed(Duration(seconds: 6));
      _flutterBlueClassicPlugin.stopScan();
      setState(() {
        status = 'Scanning completed';
      });
    }
  }

  Future<bool> pairNow(String macAddress) async {
    try {
      setState(() {
        status = 'Attempting to pair with device: $macAddress';
      });
      print('Attempting to pair with device: $macAddress');
      bool isPairingStarted =
          await _flutterBlueClassicPlugin.bondDevice(macAddress);
      if (isPairingStarted) {
        setState(() {
          print('Pairing Started');
          status = 'Pairing Started';
        });
      } else {
        print('Pairing was not able to start');
        setState(() {
          status = 'Pairing was not able to start';
        });
        throw ('Pairing was not able to start');
      }

      print('10 seconds start');
      // Wait for a few seconds and re-check pairing status
      await Future.delayed(Duration(seconds: 20));
      print('10 seconds end');

      print("fetching paired devices");
      await getPairedDevices();
      print("fetched paired devices");

      if (await isDevicePaired(macAddress)) {
        setState(() {
          isCurrentDevicePaired = true;
          status = 'paired succesfully';
        });
        print('Paired succesfully with $macAddress');
        return true;
      } else {
        print('Device is not paired');
        return false;
      }
    } catch (e) {
      print('Error during pairing: $e');
      setState(() {
        status = e.toString();
      });
      return false;
    }
  }

  //This will get already paired devices
  Future getPairedDevices() async {
    List<BluetoothDevice>? devices =
        await _flutterBlueClassicPlugin.bondedDevices;
    setState(() {
      _pairedDevices = devices;
    });
  }

  void deviceTapHandler(String macAddress) async {
    try {
      // Check if the device is already paired
      if (await isDevicePaired(macAddress)) {
        setState(() {
          status = 'Device already paired. Attempting to connect...';
          isCurrentDevicePaired = true;
        });

        // Attempt to connect to the device
        await connectToDevice(macAddress);
        return; // Exit function if paired and connection attempted
      }

      // If the device is not paired, try pairing
      setState(() {
        status = 'Device not paired. Attempting to pair...';
      });

      bool isPaired = await pairNow(macAddress);
      if (!isPaired) {
        setState(() {
          status = 'Pairing failed. Please try again.';
        });
        return; // Exit function if pairing failed
      }

      // If pairing is successful, attempt to connect
      setState(() {
        status = 'Paired successfully. Attempting to connect...';
        isCurrentDevicePaired = true;
      });

      await Future.delayed(
          Duration(seconds: 2)); // Small delay before connecting
      await connectToDevice(macAddress);
    } catch (e) {
      // Handle any unexpected errors
      setState(() {
        status = 'Error: $e';
      });
      print('Error in deviceTapHandler: $e');
    }
  }

  Future<void> resetConnectionState() async {
    try {
      // Cancel any ongoing connection attempt
      if (_currentConnection != null) {
        print('Closing existing connection...');
        await _currentConnection!.finish(); // Graceful termination
        await _currentConnection!.close(); // Hard close
        _currentConnection!.dispose(); // Release resources
        _currentConnection = null;
      }

      // Stop any active scans
      print('Stopping active scan...');
      _flutterBlueClassicPlugin.stopScan();

      // Reset connection flags
      setState(() {
        _isConnecting = false;
        isCurrentDeviceConnected = false;
        status = 'Connection state reset';
      });

      await Future.delayed(Duration(seconds: 2));

      print('Connection state has been reset.');
    } catch (e) {
      print('Error during connection state reset: $e');
    }
  }

  Future<void> connectToDevice(String macAddress) async {
    if (_isConnecting) {
      print('Already attempting to connect...');
      return;
    }

    await resetConnectionState();

    setState(() {
      _isConnecting = true;
      status = 'Initiating connection...';
    });

    try {
      // First disconnect any existing connection
      if (_currentConnection != null) {
        await _currentConnection!.close();
        _currentConnection = null;
        await Future.delayed(Duration(seconds: 2));
      }

      // Ensure Bluetooth is enabled
      bool isBluetoothEnabled = await _flutterBlueClassicPlugin.isEnabled;
      if (!isBluetoothEnabled) {
        _flutterBlueClassicPlugin.turnOn();
        await Future.delayed(Duration(seconds: 2));
      }

      // Stop any ongoing scan
      _flutterBlueClassicPlugin.stopScan();
      await Future.delayed(Duration(seconds: 1));

      setState(() {
        status = 'Attempting to connect...';
      });

      await Future.delayed(Duration(seconds: 2));
      // Connect with longer timeout
      _currentConnection = await _flutterBlueClassicPlugin
          .connect(macAddress)
          .timeout(Duration(seconds: 10));

      // Verify connection
      if (_currentConnection != null && _currentConnection!.isConnected) {
        setState(() {
          status = 'Connected successfully';
          isCurrentDeviceConnected = true;
        });
      } else {
        throw Exception('Connection verification failed');
      }
    } catch (e) {
      print('Connection error: $e');
      setState(() {
        status = 'Connection failed: ${e.toString()}';
        isCurrentDeviceConnected = false;
      });
      if (_currentConnection != null) {
        await _currentConnection!.close();
        _currentConnection = null;
      }
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> disconnectFromDevice() async {
    _reconnectTimer?.cancel();

    if (_currentConnection != null) {
      try {
        await _currentConnection!.finish(); // Try to gracefully finish first
        await Future.delayed(Duration(milliseconds: 500));
        await _currentConnection!.close();
        await Future.delayed(Duration(milliseconds: 500));
        _currentConnection!.dispose();
      } catch (e) {
        print('Error during disconnect: $e');
      }
      _currentConnection = null;
    }

    setState(() {
      isCurrentDeviceConnected = false;
      status = 'Disconnected';
    });
  }

  void handleDisconnection() {
    setState(() {
      isCurrentDeviceConnected = false;
      status = 'Device disconnected';
    });

    disconnectFromDevice();
  }

  // Add this to your dispose method
  @override
  void dispose() {
    disconnectFromDevice();
    _reconnectTimer?.cancel();
    super.dispose();
  }
  // Future<void> connectToDevice(String macAddress) async {
  //   bool isBluetoothEnabled = await _flutterBlueClassicPlugin.isEnabled;
  //   if (!isBluetoothEnabled) {
  //     _flutterBlueClassicPlugin.turnOn(); // Prompt user to enable Bluetooth
  //   }
  //   setState(() {
  //     status = 'Trying to connect...';
  //   });
  //   print('Trying to connect...');
  //   _flutterBlueClassicPlugin.stopScan();

  //   try {
  //     BluetoothConnection? connection = await _flutterBlueClassicPlugin
  //         .connect(macAddress)
  //         .timeout(Duration(seconds: 10));

  //     await Future.delayed(Duration(seconds: 5));

  //     if (connection != null && connection.isConnected) {
  //       setState(() {
  //         status = 'Device connected successfully';
  //       });
  //     } else {
  //       setState(() {
  //         status = 'Error connecting to device';
  //       });
  //     }
  //   } catch (e) {
  //     setState(() {
  //       status = 'Connection attempt timed out';
  //     });
  //     print('Error connecting: $e');
  //   }
  // }

  // Future<void> connectToDeviceWithRetry(String macAddress,
  //     {int retries = 3}) async {
  //   int attempts = 0;
  //   while (attempts < retries) {
  //     try {
  //       await connectToDevice(macAddress);
  //       return; // Exit on success
  //     } catch (e) {
  //       print('Retry attempt ${attempts + 1} failed: $e');
  //       attempts++;
  //       await Future.delayed(Duration(seconds: 2)); // Wait before retrying
  //     }
  //   }
  //   setState(() {
  //     status = 'Connection failed after $retries retries.';
  //   });
  //   print('Connection failed after $retries attempts.');
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Device status : $status',
            style: TextStyle(
              fontSize: 20,
              color: Colors.blue,
            ),
          ),
          SizedBox(
            height: 20,
          ),
          ElevatedButton(onPressed: scanPressHandler, child: Text('Scan')),
          SizedBox(
            height: 20,
          ),
          ElevatedButton(onPressed: stopPressHandler, child: Text('Stop')),
          SizedBox(
            height: 20,
          ),
          Container(
            height: MediaQuery.of(context).size.height * 0.5,
            width: MediaQuery.of(context).size.width * 0.95,
            decoration: BoxDecoration(
              color: Colors.lightBlue,
            ),
            child: SingleChildScrollView(
                child: Row(
              children: [
                //List of Discovered Devices
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Discovered Devices"),
                      for (var device in _discoveredDevices)
                        GestureDetector(
                            onTap: () {
                              deviceTapHandler(device.address);
                            },
                            child: Container(
                              height: MediaQuery.of(context).size.height * 0.04,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.pink,
                                  )),
                              child: Text(device.name ?? device.address),
                            )),
                    ],
                  ),
                ),

                //List of paired devices
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
                                border: Border.all(
                                  color: Colors.pink,
                                )),
                            child: Text(device.name ?? device.address),
                          ),
                    ],
                  ),
                ),
              ],
            )),
          )
        ],
      ),
    );
  }
}
