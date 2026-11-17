package PKG_PLACEHOLDER

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodChannel
import java.io.File

// ضغط الفيديو قبل الإرسال: أقصر ضلع 720، وبت ريت 2.5 ميجابت. أي فشل يرجع false والتطبيق يرسل الأصلي.
class VideoCompressor(private val context: Context) {
    private var current: Transformer? = null
    private var done = false

    private fun finish(result: MethodChannel.Result, ok: Boolean) {
        if (done) return
        done = true
        current = null
        try { result.success(ok) } catch (e: Throwable) {}
    }

    // الأبعاد كما تُعرض (بعد التدوير)
    private fun displaySize(path: String): IntArray? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: return null
            var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: return null
            val rot = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rot == 90 || rot == 270) { val t = w; w = h; h = t }
            intArrayOf(w, h)
        } catch (e: Throwable) {
            null
        } finally {
            try { r.release() } catch (e: Throwable) {}
        }
    }

    fun compress(inPath: String, outPath: String, result: MethodChannel.Result) {
        done = false
        try {
            if (inPath.isEmpty() || outPath.isEmpty() || !File(inPath).exists()) {
                finish(result, false)
                return
            }
            File(outPath).delete()
            val effects = ArrayList<Effect>()
            val size = displaySize(inPath)
            if (size != null) {
                val w = size[0]
                val h = size[1]
                val shortSide = minOf(w, h)
                if (shortSide > 720) {
                    val scale = 720.0 / shortSide
                    val nw = (w * scale).toInt() and 1.inv()
                    val nh = (h * scale).toInt() and 1.inv()
                    effects.add(Presentation.createForWidthAndHeight(nw, nh, Presentation.LAYOUT_SCALE_TO_FIT))
                }
            }
            val encoder = DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(2500000).build())
                .build()
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoder)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        finish(result, true)
                    }

                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        try { File(outPath).delete() } catch (e: Throwable) {}
                        finish(result, false)
                    }
                })
                .build()
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(inPath))))
                .setEffects(Effects(ArrayList<AudioProcessor>(), effects))
                .build()
            current = transformer
            transformer.start(item, outPath)
        } catch (e: Throwable) {
            finish(result, false)
        }
    }

    fun cancel() {
        try { current?.cancel() } catch (e: Throwable) {}
        current = null
    }
}
