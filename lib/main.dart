import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sensor_capture',
      home: const SensorCameraPage(),
    );
  }
}

class SensorCameraPage extends StatefulWidget {
  const SensorCameraPage({super.key});

  @override
  State<SensorCameraPage> createState() => _SensorCameraPageState();
}

class _SensorCameraPageState extends State<SensorCameraPage> {
  CameraController? _cameraController;
  Timer? _timer;
  final List<Map<String, dynamic>> _recordingData = [];
  final List<String> _logHistory = [];
  final TextEditingController _intervalController =
  TextEditingController(text: "500");

  // センサーデータ
  double _accX = 0, _accY = 0, _accZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  double _magX = 0, _magY = 0, _magZ = 0;

  String? _currentRecordingDir;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();

    if (cameras.isNotEmpty) {
      _cameraController =
          CameraController(cameras[0], ResolutionPreset.medium);
      _cameraController?.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }

    // 加速度センサー
    accelerometerEvents.listen((event) {
      setState(() {
        _accX = event.x;
        _accY = event.y;
        _accZ = event.z;
      });
    });

    // ジャイロスコープ
    gyroscopeEvents.listen((event) {
      setState(() {
        _gyroX = event.x;
        _gyroY = event.y;
        _gyroZ = event.z;
      });
    });

    // 地磁気センサー
    magnetometerEvents.listen((event) {
      setState(() {
        _magX = event.x;
        _magY = event.y;
        _magZ = event.z;
      });
    });
  }

  void _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showMessage("Camera not initialized");
      return;
    }

    if (_isRecording) {
      _showMessage("Already recording");
      return;
    }

    final intervalMs = int.tryParse(_intervalController.text) ?? 500;
    if (intervalMs <= 0) {
      _showMessage("Invalid interval");
      return;
    }

    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final folderName = "record_${DateTime.now().millisecondsSinceEpoch}";
      final folderPath = "${baseDir.path}/$folderName";
      final dir = Directory(folderPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      _currentRecordingDir = folderPath;
    } catch (e) {
      _showMessage("Failed to create directory: $e");
      return;
    }

    _isRecording = true;
    _recordingData.clear();

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      final timestamp = DateTime.now();
      final fileName = "img_${timestamp.millisecondsSinceEpoch}.jpg";
      final filePath = "$_currentRecordingDir/$fileName";

      try {
        XFile file = await _cameraController!.takePicture();
        await file.saveTo(filePath);

        _recordingData.add({
          'timestamp': timestamp.toIso8601String(),
          'acc': '$_accX,$_accY,$_accZ',
          'gyro': '$_gyroX,$_gyroY,$_gyroZ',
          'magnet': '$_magX,$_magY,$_magZ',
          'img_path': filePath,
        });

        setState(() {
          _logHistory.insert(
            0,
            "${timestamp.toIso8601String()} | "
                "acc(${_accX.toStringAsFixed(1)},${_accY.toStringAsFixed(1)},${_accZ.toStringAsFixed(1)}) | $fileName",
          );
        });
      } catch (e) {
        debugPrint("Error capturing image: $e");
      }
    });

    _showMessage("Recording started");
  }

  void _stopRecording() async {
    if (!_isRecording) {
      _showMessage("Not recording");
      return;
    }

    _timer?.cancel();
    _isRecording = false;

    if (_currentRecordingDir != null && _recordingData.isNotEmpty) {
      final csvFileName = "record.csv";
      final csvFilePath = "$_currentRecordingDir/$csvFileName";

      try {
        List<List<dynamic>> rows = [
          [
            "timestamp",
            "acc_x",
            "acc_y",
            "acc_z",
            "gyro_x",
            "gyro_y",
            "gyro_z",
            "mag_x",
            "mag_y",
            "mag_z",
            "filename",
            "filepath"
          ]
        ];
        for (var record in _recordingData) {
          rows.add([
            record["timestamp"],
            record["acc_x"],
            record["acc_y"],
            record["acc_z"],
            record["gyro_x"],
            record["gyro_y"],
            record["gyro_z"],
            record["mag_x"],
            record["mag_y"],
            record["mag_z"],
            record["filename"],
            record["filepath"],
          ]);
        }

        String csv = const ListToCsvConverter().convert(rows);
        final file = File(csvFilePath);
        await file.writeAsString(csv);

        _showMessage(
            "Saved: $_currentRecordingDir (${_recordingData.length} records)");
      } catch (e) {
        _showMessage("Failed to save CSV: $e");
      }

      _recordingData.clear();
      _currentRecordingDir = null;
    } else {
      _showMessage("No data to save");
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // CSV確認機能
  Future<void> _viewRecordings() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(baseDir.path);
    final folders = dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('record_'))
        .toList();

    if (!mounted) return;

    if (folders.isEmpty) {
      _showMessage("No recordings found");
      return;
    }

    // フォルダ一覧を表示
    showDialog(
      context: context,
      builder: (context) => RecordingsDialog(folders: folders),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("sensor_capture"),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _viewRecordings,
            tooltip: "View Recordings",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text("Interval(ms): "),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _isRecording ? null : _startRecording,
                  child: const Text("Start"),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isRecording ? _stopRecording : null,
                  child: const Text("Stop"),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              SizedBox(height: 150, child: CameraPreview(_cameraController!)),
            const SizedBox(height: 20),
            // センサーデータ表示
            Row(
              children: [
                Expanded(
                  child: _buildSensorBox(
                      "Accelerometer", _accX, _accY, _accZ, Colors.blue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSensorBox(
                      "Gyroscope", _gyroX, _gyroY, _gyroZ, Colors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSensorBox(
                      "Magnetometer", _magX, _magY, _magZ, Colors.purple),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ステータス表示
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red.shade50 : Colors.grey.shade100,
                border: Border.all(
                    color: _isRecording ? Colors.red : Colors.grey, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isRecording
                        ? Icons.fiber_manual_record
                        : Icons.stop_circle,
                    color: _isRecording ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isRecording
                        ? "Recording... (${_recordingData.length} records)"
                        : "Stopped",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isRecording ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration:
                BoxDecoration(border: Border.all(color: Colors.black)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Log",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _logHistory.length,
                        itemBuilder: (context, index) {
                          return Text(
                            _logHistory[index],
                            style: const TextStyle(fontSize: 11),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorBox(
      String title, double x, double y, double z, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 11, color: color)),
          const SizedBox(height: 4),
          Text("X: ${x.toStringAsFixed(1)}", style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
          Text("Y: ${y.toStringAsFixed(1)}", style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
          Text("Z: ${z.toStringAsFixed(1)}", style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// CSV確認ダイアログ
class RecordingsDialog extends StatelessWidget {
  final List<Directory> folders;

  const RecordingsDialog({super.key, required this.folders});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Recordings"),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            final folderName = folder.path.split('/').last;
            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(folderName),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        CsvViewerPage(folderPath: folder.path),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }
}

// CSV表示ページ
class CsvViewerPage extends StatefulWidget {
  final String folderPath;

  const CsvViewerPage({super.key, required this.folderPath});

  @override
  State<CsvViewerPage> createState() => _CsvViewerPageState();
}

class _CsvViewerPageState extends State<CsvViewerPage> {
  List<List<dynamic>> _csvData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCsv();
  }

  Future<void> _loadCsv() async {
    try {
      final csvFile = File("${widget.folderPath}/record.csv");
      if (await csvFile.exists()) {
        final csvString = await csvFile.readAsString();
        final csvData =
        const CsvToListConverter().convert(csvString, eol: '\n');
        setState(() {
          _csvData = csvData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint("Error loading CSV: $e");
    }
  }

  Future<void> _shareCsv() async {
    final csvFile = File("${widget.folderPath}/record.csv");
    if (await csvFile.exists()) {
      await Share.shareXFiles(
        [XFile(csvFile.path)],
        subject: 'Sensor Recording CSV',
        text: 'Sharing sensor recording data',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final folderName = widget.folderPath.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: Text(folderName),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _csvData.isEmpty ? null : _shareCsv,
            tooltip: "Share CSV",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _csvData.isEmpty
          ? const Center(child: Text("No CSV data found"))
          : SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: _csvData[0]
                .map((col) => DataColumn(
                label: Text(col.toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12))))
                .toList(),
            rows: _csvData
                .skip(1)
                .map(
                  (row) => DataRow(
                cells: row
                    .map((cell) => DataCell(Text(
                    cell.toString(),
                    style: const TextStyle(fontSize: 11))))
                    .toList(),
              ),
            )
                .toList(),
          ),
        ),
      ),
    );
  }
}