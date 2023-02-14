package com.example.camera_stream_bug

import androidx.annotation.NonNull
import io.flutter.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfByte
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.nio.ByteBuffer

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.camera_stream_bug.method_channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call, result -> methodCallHandler(call, result)
            }
    }

    private fun methodCallHandler(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cvtColor") {
            val bytes = call.argument<ByteArray>("bytes")
            val outputType = call.argument<Int>("outputType")
            val width = call.argument<Int>("width")
            val height = call.argument<Int>("height")
            if (bytes == null || outputType == null || width == null || height == null) {
                result.error("ArgumentError", "input is invalid", "")
                return
            }

            try {
                result.success(cvtColor(width, height, bytes, outputType))
            } catch (e: java.lang.Exception) {
                result.error("error", "Error from opencv: ${e.message}", null)
            }
        } else {
            result.notImplemented()
        }
    }

    private fun cvtColor(width: Int, height: Int, input: ByteArray, outputType: Int): ByteArray {
        if (!OpenCVLoader.initDebug()) {
            throw Exception("Error initializing opencv")
        }

        val src = Mat((height * 1.5).toInt(), width, CvType.CV_8UC1)
        src.put(0, 0, input)
        val dst = Mat(height, width, CvType.CV_8UC3)

        Imgproc.cvtColor(src, dst, outputType)

        val matOfByte = MatOfByte()
        Imgcodecs.imencode(".bmp", dst, matOfByte)
        return matOfByte.toArray()
    }
}
