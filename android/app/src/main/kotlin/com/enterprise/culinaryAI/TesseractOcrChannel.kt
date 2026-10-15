package com.enterprise.culinaryAI

import android.content.Context
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Runs Tesseract on a dedicated worker because recognition is blocking and
 * TessBaseAPI instances are not thread-safe.
 */
class TesseractOcrChannel(
    private val context: Context,
    flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL_NAME,
    )
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    @Volatile
    private var isClosed = false
    private var tessBaseApi: TessBaseAPI? = null

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_RECOGNIZE) {
            result.notImplemented()
            return
        }

        val imagePath = call.argument<String>(ARG_IMAGE_PATH)
        if (imagePath.isNullOrBlank()) {
            result.error(ERROR_INVALID_ARGUMENT, "A receipt image path is required.", null)
            return
        }

        try {
            worker.execute {
                recognize(imagePath, result)
            }
        } catch (_: RejectedExecutionException) {
            result.error(ERROR_UNAVAILABLE, "The OCR engine is shutting down.", null)
        }
    }

    private fun recognize(
        imagePath: String,
        result: MethodChannel.Result,
    ) {
        try {
            val imageFile = File(imagePath)
            require(imageFile.isFile) { "The selected receipt image no longer exists." }

            val tess = getOrCreateEngine()
            tess.setImage(imageFile)
            val hocr = tess.getHOCRText(0).orEmpty()
            val text = tess.getUTF8Text().orEmpty()
            tess.clear()

            postResult {
                result.success(mapOf("hocr" to hocr, "text" to text))
            }
        } catch (error: Throwable) {
            recycleEngine()
            postResult {
                result.error(
                    ERROR_RECOGNITION_FAILED,
                    error.message ?: "Tesseract could not read this receipt.",
                    null,
                )
            }
        }
    }

    private fun getOrCreateEngine(): TessBaseAPI {
        tessBaseApi?.let { return it }

        val dataDirectory = ensureLanguageModel()
        val engine = TessBaseAPI()
        val initialized = engine.init(
            dataDirectory.absolutePath,
            LANGUAGE,
            TessBaseAPI.OEM_LSTM_ONLY,
            mapOf(
                "load_system_dawg" to "0",
                "load_freq_dawg" to "0",
                "preserve_interword_spaces" to "1",
                "user_defined_dpi" to "300",
            ),
        )
        if (!initialized) {
            engine.recycle()
            error("Tesseract failed to initialize its English language model.")
        }

        engine.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_COLUMN)
        tessBaseApi = engine
        return engine
    }

    private fun ensureLanguageModel(): File {
        val dataDirectory = File(context.filesDir, DATA_DIRECTORY)
        val tessDataDirectory = File(dataDirectory, "tessdata")
        if (!tessDataDirectory.exists() && !tessDataDirectory.mkdirs()) {
            error("Could not create the Tesseract data directory.")
        }

        val modelFile = File(tessDataDirectory, MODEL_FILENAME)
        if (modelFile.isFile && modelFile.length() == MODEL_SIZE_BYTES) {
            return dataDirectory
        }

        val temporaryFile = File(tessDataDirectory, "$MODEL_FILENAME.tmp")
        val assetLookupKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(MODEL_ASSET_PATH)
        context.assets.open(assetLookupKey).use { input ->
            FileOutputStream(temporaryFile, false).use { output ->
                input.copyTo(output)
            }
        }
        check(temporaryFile.length() == MODEL_SIZE_BYTES) {
            "The bundled Tesseract language model is incomplete."
        }

        if (modelFile.exists() && !modelFile.delete()) {
            error("Could not replace the Tesseract language model.")
        }
        if (!temporaryFile.renameTo(modelFile)) {
            temporaryFile.copyTo(modelFile, overwrite = true)
            if (!temporaryFile.delete()) temporaryFile.deleteOnExit()
        }
        return dataDirectory
    }

    private fun postResult(callback: () -> Unit) {
        if (!isClosed) callback()
    }

    private fun recycleEngine() {
        tessBaseApi?.recycle()
        tessBaseApi = null
    }

    fun close() {
        if (isClosed) return
        isClosed = true
        channel.setMethodCallHandler(null)
        try {
            worker.execute(::recycleEngine)
        } catch (_: RejectedExecutionException) {
            recycleEngine()
        }
        worker.shutdown()
    }

    private companion object {
        const val CHANNEL_NAME = "culinary_ai/tesseract"
        const val METHOD_RECOGNIZE = "recognize"
        const val ARG_IMAGE_PATH = "imagePath"

        const val ERROR_INVALID_ARGUMENT = "invalid_argument"
        const val ERROR_RECOGNITION_FAILED = "recognition_failed"
        const val ERROR_UNAVAILABLE = "ocr_unavailable"

        const val LANGUAGE = "eng"
        const val DATA_DIRECTORY = "tesseract-v1"
        const val MODEL_FILENAME = "eng.traineddata"
        const val MODEL_ASSET_PATH = "assets/tessdata/eng.traineddata"
        const val MODEL_SIZE_BYTES = 15_400_601L
    }
}
