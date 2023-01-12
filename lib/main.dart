import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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
  CameraController? _controller;
  Image? _imageData;
  CameraImage? _cameraImage;

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
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }

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
    print('onFrame');
    _stopStream();

    // final res = await convertYUV420toImageColor(frame);
    final res = await _convertYUV420Black(frame);
    setState(() {
      _imageData = res;
      _cameraImage = frame;
    });
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

  Future<Image?> convertYuvToImage(CameraImage image) async {
    int imageWidth = image.width;
    int imageHeight = image.height;
    // ARGB array needed by Bitmap static factory method I use below.
    final argbArray = Uint8List(imageWidth * imageHeight);
    ByteBuffer yBuffer = image.planes[0].bytes.buffer;

    // A YUV Image could be implemented with planar or semi planar layout.
    // A planar YUV image would have following structure:
    // YYYYYYYYYYYYYYYY
    // ................
    // UUUUUUUU
    // ........
    // VVVVVVVV
    // ........
    //
    // While a semi-planar YUV image would have layout like this:
    // YYYYYYYYYYYYYYYY
    // ................
    // UVUVUVUVUVUVUVUV   <-- Interleaved UV channel
    // ................
    // This is defined by row stride and pixel strides in the planes of the
    // image.

    // Plane 1 is always U & plane 2 is always V
    // https://developer.android.com/reference/android/graphics/ImageFormat#YUV_420_888
    ByteBuffer uBuffer = image.planes[1].bytes.buffer;
    ByteBuffer vBuffer = image.planes[2].bytes.buffer;

    // The U/V planes are guaranteed to have the same row stride and pixel
    // stride.
    int yRowStride = image.planes[0].bytesPerRow;
    int yPixelStride = image.planes[0].bytesPerPixel!;
    int uvRowStride = image.planes[1].bytesPerRow;
    int uvPixelStride = image.planes[1].bytesPerPixel!;

    int r, g, b;
    int yValue, uValue, vValue;

    var img = imglib.Image(imageWidth, imageHeight); // Create Image buffer

    for (int y = 0; y < imageHeight; ++y) {
      for (int x = 0; x < imageWidth; ++x) {
        int yIndex = (y * yRowStride) + (x * yPixelStride);
        // Y plane should have positive values belonging to [0...255]
        yValue = (yBuffer.asUint8List()[yIndex] & 0xff);

        int uvx = x ~/ 2;
        int uvy = y ~/ 2;
        // U/V Values are subsampled i.e. each pixel in U/V chanel in a
        // YUV_420 image act as chroma value for 4 neighbouring pixels
        int uvIndex = (uvy * uvRowStride) + (uvx * uvPixelStride);

        // U/V values ideally fall under [-0.5, 0.5] range. To fit them into
        // [0, 255] range they are scaled up and centered to 128.
        // Operation below brings U/V values to [-128, 127].
        uValue = (uBuffer.asUint8List()[uvIndex] & 0xff) - 128;
        vValue = (vBuffer.asUint8List()[uvIndex] & 0xff) - 128;

        // Compute RGB values per formula above.
        r = (yValue + 1.370705 * vValue).toInt();
        g = (yValue - (0.698001 * vValue) - (0.337633 * uValue)).toInt();
        b = (yValue + 1.732446 * uValue).toInt();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        // Use 255 for alpha value, no transparency. ARGB values are
        // positioned in each byte of a single 4 byte integer
        // [AAAAAAAARRRRRRRRGGGGGGGGBBBBBBBB]
        int argbIndex = y * imageWidth + x;
        img[argbIndex] =
            (255 << 24) | (r & 255) << 16 | (g & 255) << 8 | (b & 255);
      }
    }

    imglib.PngEncoder pngEncoder = new imglib.PngEncoder(level: 0, filter: 0);
    List<int> png = pngEncoder.encodeImage(img);
    return Image.memory(Uint8List.fromList(png));
  }

  /// convert camera image to color image to be displayed
  Future<Image?> convertYUV420toImageColor(CameraImage image) async {
    final concatenated = Uint8List.fromList(
      [
        ...image.planes[0].bytes,
        ...image.planes[1].bytes,
        ...image.planes[2].bytes,
      ],
    );

    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    // final path = await getExternalStorageDirectory();
    final path = Directory('/storage/emulated/0/Download');
    final file = File('${path.path}/img.yuv');
    await file.writeAsBytes(concatenated);

    const shift = (0xFF << 24);

    try {
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel!;

      print("uvRowStride: " + uvRowStride.toString());
      print("uvPixelStride: " + uvPixelStride.toString());

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
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_imageData != null && _cameraImage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Image
          Center(
            child: Image(
              image: _imageData!.image,
              fit: BoxFit.fitWidth,
            ),
          ),

          /// Spacer
          const SizedBox(height: 24),

          /// Stats
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
      );
    }

    if (_controller != null && _controller!.value.isInitialized) {
      print('aspect ratio: ${_controller!.value.aspectRatio}');

      return Center(
        child: AspectRatio(
          aspectRatio: 1 / _controller!.value.aspectRatio,
          child: CameraPreview(
            _controller!,
          ),
        ),
      );
    }

    return const CupertinoActivityIndicator();
  }
}
