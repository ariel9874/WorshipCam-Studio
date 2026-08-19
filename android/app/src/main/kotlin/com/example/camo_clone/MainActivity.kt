package com.example.camo_clone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.YuvImage
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.graphics.Matrix
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.camo_clone/yuv_converter"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "convertYuv420ToJpeg") {
                try {
                    val yBytes = call.argument<ByteArray>("y")!!
                    val uBytes = call.argument<ByteArray>("u")!!
                    val vBytes = call.argument<ByteArray>("v")!!
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    val yRowStride = call.argument<Int>("yRowStride")!!
                    val uvRowStride = call.argument<Int>("uvRowStride")!!
                    val uvPixelStride = call.argument<Int>("uvPixelStride")!!
                    val quality = call.argument<Int>("quality") ?: 85
                    val rotation = call.argument<Int>("rotation") ?: 0

                    // Convert YUV_420_888 to NV21 format (which YuvImage supports)
                    val nv21 = yuv420ToNv21(yBytes, uBytes, vBytes, width, height, yRowStride, uvRowStride, uvPixelStride)
                    
                    // Use Android's hardware-accelerated JPEG encoder
                    val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                    val jpegStream = ByteArrayOutputStream()
                    yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, jpegStream)
                    
                    if (rotation == 0) {
                        result.success(jpegStream.toByteArray())
                    } else {
                        // Rotate the JPEG using Bitmap + Matrix
                        val jpegBytes = jpegStream.toByteArray()
                        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                        val matrix = Matrix()
                        matrix.postRotate(rotation.toFloat())
                        val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                        
                        val outputStream = ByteArrayOutputStream()
                        rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
                        
                        bitmap.recycle()
                        rotatedBitmap.recycle()
                        
                        result.success(outputStream.toByteArray())
                    }
                } catch (e: Exception) {
                    result.error("CONVERSION_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun yuv420ToNv21(
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        width: Int,
        height: Int,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int
    ): ByteArray {
        val nv21 = ByteArray(width * height * 3 / 2)
        
        // Copy Y plane
        if (yRowStride == width) {
            System.arraycopy(yBytes, 0, nv21, 0, width * height)
        } else {
            for (row in 0 until height) {
                System.arraycopy(yBytes, row * yRowStride, nv21, row * width, width)
            }
        }
        
        // Interleave V and U into NV21 format (VU order)
        val chromaOffset = width * height
        val halfWidth = width / 2
        val halfHeight = height / 2
        
        if (uvPixelStride == 2 && uvRowStride == width) {
            // Fast path: data is already semi-planar (common on many devices)
            for (i in 0 until halfWidth * halfHeight) {
                nv21[chromaOffset + i * 2] = vBytes[i * uvPixelStride]
                nv21[chromaOffset + i * 2 + 1] = uBytes[i * uvPixelStride]
            }
        } else {
            // General path
            for (row in 0 until halfHeight) {
                for (col in 0 until halfWidth) {
                    val uvIndex = row * uvRowStride + col * uvPixelStride
                    val nv21Index = chromaOffset + row * width + col * 2
                    nv21[nv21Index] = vBytes[uvIndex]
                    nv21[nv21Index + 1] = uBytes[uvIndex]
                }
            }
        }
        
        return nv21
    }
}
