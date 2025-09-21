import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';

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
      title: 'sensor_capture', // タイトル
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
  // カメラコントローラ
  CameraController? _cameraController;

  // 記録タイマー
  Timer? _timer;

  // 過去記録
  final List<String> _history = [];

  // 記録間隔(ms)
  final TextEditingController _intervalController = TextEditingController(text: "500");

  // 現在の加速度
  double _x = 0, _y = 0, _z = 0;

  @override
  void initState() {
    super.initState();

    // カメラ初期化
    if (cameras.isNotEmpty) {
      _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
      _cameraController?.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }

    // 加速度センサー購読
    accelerometerEvents.listen((event) {
      setState(() {
        _x = event.x;
        _y = event.y;
        _z = event.z;
      });
    });
  }

  // 記録開始
  void _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera not initialized")),
      );
      return;
    }

    final intervalMs = int.tryParse(_intervalController.text) ?? 500;
    _timer?.cancel();

    // 保存先ディレクトリ取得
    final dir = await getApplicationDocumentsDirectory();

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      final timestamp = DateTime.now();
      final fileName = "img_${timestamp.millisecondsSinceEpoch}.jpg";
      final filePath = "${dir.path}/$fileName";

      try {
        // 撮影
        XFile file = await _cameraController!.takePicture();
        await file.saveTo(filePath);

        // 履歴に追加（timestamp, accel, fileName）
        setState(() {
          _history.insert(
              0,
              "${timestamp.toIso8601String()} | x:${_x.toStringAsFixed(2)} "
              "y:${_y.toStringAsFixed(2)} z:${_z.toStringAsFixed(2)} | $fileName");
        });
      } catch (e) {
        print("Camera error: $e");
      }
    });
  }

  // 記録停止
  void _stopRecording() {
    _timer?.cancel();
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
      appBar: AppBar(title: const Text("sensor_capture")), // 表示も英語
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 記録設定
            Row(
              children: [
                const Text("Interval(ms): "), // 英語
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(onPressed: _startRecording, child: const Text("Start")), // 英語
                const SizedBox(width: 10),
                ElevatedButton(onPressed: _stopRecording, child: const Text("Stop")), // 英語
              ],
            ),
            const SizedBox(height: 20),

            // カメラプレビュー
            if (_cameraController != null && _cameraController!.value.isInitialized)
              SizedBox(height: 200, child: CameraPreview(_cameraController!)),
            const SizedBox(height: 20),

            // 現在値表示
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: Colors.blue, width: 2)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(children: [const Text("X"), Text(_x.toStringAsFixed(2))]),
                  Column(children: [const Text("Y"), Text(_y.toStringAsFixed(2))]),
                  Column(children: [const Text("Z"), Text(_z.toStringAsFixed(2))]),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 過去記録表示
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey, width: 1)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Log", style: TextStyle(fontWeight: FontWeight.bold)), // 英語
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          return Text(_history[index]);
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
}