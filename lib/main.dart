import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:opencv_4/factory/pathfrom.dart';
import 'package:opencv_4/opencv_4.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const platform = MethodChannel('com.camera_stream_bug.method_channel');

  CameraController? _controller;
  Image? _imageData;
  CameraImage? _cameraImage;
  var counter = 0;

  @override
  void initState() {
    super.initState();

    _startCamera();
  }

  Future<void> _startCamera() async {
    final cameras = await availableCameras();

    _controller = CameraController(
      cameras.firstWhere(
        (final e) => e.lensDirection == CameraLensDirection.back,
      ),
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller?.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      _startStream();
      setState(() {});
    });
  }

  void _startStream() {
    _controller?.startImageStream(_onFrame);
  }

  void _stopStream() {
    _controller?.stopImageStream();
  }

  Future<void> _onFrame(final CameraImage frame) async {
    // if (counter != 10) {
    //   counter++;
    //   return;
    // }
    _stopStream();

    print(
        'onFrame | planes: ${frame.planes.length} | rotation: ${_controller!.description.sensorOrientation} | bytes: ${frame.planes[0].bytes[100]} | frame.format.group: ${frame.format.group}');
    // _stopStream();

    // if (frame.format.group == ImageFormatGroup.nv21) {
    final start = DateTime.now();
    // NV21
    final res = await convertNV21ToPng(frame);
    setState(() {
      _imageData = res;
      _cameraImage = frame;
    });
    print('Time: ${DateTime.now().difference(start).inMilliseconds}ms');
    // } else if (frame.planes.length == 1) {
    //   // JPEG
    //   final res = Image.memory(frame.planes.first.bytes);
    //   setState(() {
    //     _imageData = res;
    //     _cameraImage = frame;
    //   });
    // } else {
    //   // final res = await convertYUV420toImageColor(frame);
    //   final res = await _convertYUV420Black(frame);
    //   setState(() {
    //     _imageData = res;
    //     _cameraImage = frame;
    //   });
    // }
    counter = 0;
  }

  Uint8List decodeYUV(Uint8List fg, int width, int height) {
    final out = Uint8List(width * height);

    int sz = width * height;
    int i, j;
    int Y, Cr = 0, Cb = 0;
    for (j = 0; j < height; j++) {
      int pixPtr = j * width;
      final int jDiv2 = j >> 1;
      for (i = 0; i < width; i++) {
        Y = fg[pixPtr];
        if (Y < 0) Y += 255;
        if ((i & 0x1) != 1) {
          final int cOff = sz + jDiv2 * width + (i >> 1) * 2;
          Cb = fg[cOff];
          if (Cb < 0)
            Cb += 127;
          else
            Cb -= 128;
          Cr = fg[cOff + 1];
          if (Cr < 0)
            Cr += 127;
          else
            Cr -= 128;
        }
        int R = Y + Cr + (Cr >> 2) + (Cr >> 3) + (Cr >> 5);
        if (R < 0)
          R = 0;
        else if (R > 255) R = 255;
        int G = Y -
            (Cb >> 2) +
            (Cb >> 4) +
            (Cb >> 5) -
            (Cr >> 1) +
            (Cr >> 3) +
            (Cr >> 4) +
            (Cr >> 5);
        if (G < 0)
          G = 0;
        else if (G > 255) G = 255;
        int B = Y + Cb + (Cb >> 1) + (Cb >> 2) + (Cb >> 6);
        if (B < 0)
          B = 0;
        else if (B > 255) B = 255;
        out[pixPtr++] = 0xff000000 + (B << 16) + (G << 8) + R;
      }
    }
    return out;
  }

  Uint8List yuv2rgb(Uint8List yuv, int width, int height) {
    int total = width * height;
    final rgb = Uint8List(total);
    int Y, Cb = 0, Cr = 0, index = 0;
    int R, G, B;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        Y = yuv[y * width + x];
        if (Y < 0) Y += 255;

        if ((x & 1) == 0) {
          Cr = yuv[(y >> 1) * (width) + x + total];
          Cb = yuv[(y >> 1) * (width) + x + total + 1];

          if (Cb < 0)
            Cb += 127;
          else
            Cb -= 128;
          if (Cr < 0)
            Cr += 127;
          else
            Cr -= 128;
        }

        R = Y + Cr + (Cr >> 2) + (Cr >> 3) + (Cr >> 5);
        G = Y -
            (Cb >> 2) +
            (Cb >> 4) +
            (Cb >> 5) -
            (Cr >> 1) +
            (Cr >> 3) +
            (Cr >> 4) +
            (Cr >> 5);
        B = Y + Cb + (Cb >> 1) + (Cb >> 2) + (Cb >> 6);

        // Approximation
//				R = (int) (Y + 1.40200 * Cr);
//			    G = (int) (Y - 0.34414 * Cb - 0.71414 * Cr);
//				B = (int) (Y + 1.77200 * Cb);

        if (R < 0)
          R = 0;
        else if (R > 255) R = 255;
        if (G < 0)
          G = 0;
        else if (G > 255) G = 255;
        if (B < 0)
          B = 0;
        else if (B > 255) B = 255;

        rgb[index++] = 0xff000000 + (R << 16) + (G << 8) + B;
      }
    }

    return rgb;
  }

  /// Converts one YUV pixel to RGB
  List<int> yuv2rgbPixel(int yValue, int uValue, int vValue) {
    int r, g, b;

    var rTmp = yValue + (1.370705 * (vValue - 128));
    var gTmp =
        yValue - (0.698001 * (vValue - 128)) - (0.337633 * (uValue - 128));
    var bTmp = yValue + (1.732446 * (uValue - 128));
    r = max(0, min(255, rTmp.toInt()));
    g = max(0, min(255, gTmp.toInt()));
    b = max(0, min(255, bTmp.toInt()));

    return [r, g, b];
  }

  Future<Image?> convertNV21ToPng(CameraImage image) async {
    final res = await platform.invokeMethod<Uint8List>(
      'cvtColor',
      {
        'bytes': concatenatePlanes(image.planes),
        // 'bytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'outputType': Cv2.COLOR_YUV2BGRA_NV21,
      },
    );

    return Image.memory(res!);
  }

  Future<Image?> _convertYUV420Black(CameraImage image) async {
    var img = imglib.Image(image.width, image.height); // Create Image buffer

    Plane plane = image.planes[0];
    const int shift = (0xFF << 24);

    // Fill image buffer with plane[0] from YUV420_888
    for (int x = 0; x < image.width; x++) {
      for (int planeOffset = 0;
          planeOffset < image.height * image.width;
          planeOffset += image.width) {
        final pixelColor = plane.bytes[planeOffset + x];
        // color: 0x FF  FF  FF  FF
        //           A   B   G   R
        // Calculate pixel color
        var newVal =
            shift | (pixelColor << 16) | (pixelColor << 8) | pixelColor;

        img.data[planeOffset + x] = newVal;
      }
    }

    imglib.PngEncoder pngEncoder = new imglib.PngEncoder(level: 0, filter: 0);
    List<int> png = pngEncoder.encodeImage(img);
    return Image.memory(Uint8List.fromList(png));
  }

  /// convert camera image to color image to be displayed
  Future<Image?> convertYUV420toImageColor(CameraImage image) async {
    // final concatenated = Uint8List.fromList(
    //   [
    //     ...image.planes[0].bytes,
    //     ...image.planes[1].bytes,
    //     ...image.planes[2].bytes,
    //   ],
    // );

    // await Permission.storage.request();
    // await Permission.manageExternalStorage.request();

    /// Uncomment to write frame to file
    // final path = await getExternalStorageDirectory();
    // final path = Directory('/storage/emulated/0/Download');
    // final file = File('${path.path}/img.yuv');
    // await file.writeAsBytes(concatenated);

    const shift = (0xFF << 24);

    try {
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel!;

      // imgLib -> Image package from https://pub.dartlang.org/packages/image
      var img = imglib.Image(width, height); // Create Image buffer

      // Fill image buffer with plane[0] from YUV420_888
      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = image.planes[0].bytes[index];
          final up = image.planes[1].bytes[uvIndex];
          final vp = image.planes[2].bytes[uvIndex];
          // Calculate pixel color
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

          // color: 0x FF  FF  FF  FF
          //           A   B   G   R
          img.data[index] = shift | (b << 16) | (g << 8) | r;
        }
      }

      imglib.PngEncoder pngEncoder = new imglib.PngEncoder(level: 0, filter: 0);
      List<int> png = pngEncoder.encodeImage(img);

      print('returning image');
      return Image.memory(Uint8List.fromList(png));
    } catch (e, s) {
      print("$s\n>>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

  Uint8List concatenatePlanes(final List<Plane> planes) {
    var totalBytes = 0;
    for (var i = 0; i < planes.length; ++i) {
      totalBytes += planes[i].bytes.length;
    }
    final pointer = calloc<ffi.Uint8>(totalBytes);
    final bytes = pointer.asTypedList(totalBytes);
    var byteOffset = 0;
    for (var i = 0; i < planes.length; ++i) {
      final length = planes[i].bytes.length;
      bytes.setRange(byteOffset, byteOffset += length, planes[i].bytes);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_controller != null && _controller!.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: CameraPreview(
                _controller!,
              ),
            ),
          )
        else
          const CupertinoActivityIndicator(),

        // Image preview
        if (_imageData != null && _cameraImage != null) ...[
          Positioned(
            top: 0,
            left: 0,
            child: SizedBox(
              width: 480,
              child: Transform.rotate(
                angle: _controller!.description.sensorOrientation * pi / 180,
                child: Image(
                  image: _imageData!.image,
                  fit: BoxFit.fitWidth,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              padding: EdgeInsets.all(24),
              color: Colors.black87,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'width: ${_cameraImage!.width}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),
                  Text(
                    'height: ${_cameraImage!.height}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),

                  /// Spacer
                  const SizedBox(height: 10),

                  Text(
                    'plane 0 len: ${_cameraImage!.planes[0].bytes.length}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),
                  Text(
                    'plane 0 bytesPerPixel: ${_cameraImage!.planes[0].bytesPerPixel}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),
                  Text(
                    'plane 0 bytesPerRow: ${_cameraImage!.planes[0].bytesPerRow}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),

                  // For YUV
                  if (_cameraImage!.planes.length > 1) ...[
                    /// Spacer
                    const SizedBox(height: 10),

                    Text(
                      'plane 1 len: ${_cameraImage!.planes[1].bytes.length}',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                    Text(
                      'plane 1 bytesPerPixel: ${_cameraImage!.planes[1].bytesPerPixel}',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                    Text(
                      'plane 1 bytesPerRow: ${_cameraImage!.planes[1].bytesPerRow}',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.left,
                    ),

                    /// Spacer
                    const SizedBox(height: 10),

                    Text(
                      'plane 2 len: ${_cameraImage!.planes[2].bytes.length}',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                    Text(
                      'plane 2 bytesPerPixel: ${_cameraImage!.planes[2].bytesPerPixel}',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                    Text(
                      'plane 2 bytesPerRow: ${_cameraImage!.planes[2].bytesPerRow}',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ],
              ),
            ),
          )
        ],
      ],
    );
  }
}
