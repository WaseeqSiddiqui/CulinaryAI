package com.enterprise.culinaryAI

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var tesseractOcrChannel: TesseractOcrChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tesseractOcrChannel = TesseractOcrChannel(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        tesseractOcrChannel?.close()
        tesseractOcrChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
