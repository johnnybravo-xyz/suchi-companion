package app.suchi.page

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

class ShareChannel(private val activity: FlutterActivity) {
    private companion object {
        const val CHANNEL_NAME = "app.suchi.page/share"
        const val STORE_NAME = "suchi-share-imports"
        const val BATCH_ID_EXTRA = "app.suchi.page.share.BATCH_ID"
        const val PICKER_REQUEST = 4721
        const val PICKER_PREFERENCES = "suchi-share-picker"
        const val PENDING_PICKER_BATCH = "pending_batch_id"
        const val MANIFEST_VERSION = 1
        const val MAX_ITEMS = 20
        const val MAX_INPUTS = 10_000
        const val MAX_MANIFEST_BYTES = 1 shl 20
        const val COPY_BUFFER_SIZE = 64 * 1024
        val SUPPORTED_MIME_TYPES =
            setOf(
                "application/pdf",
                "image/jpeg",
                "image/png",
                "image/heic",
                "image/heif",
            )
        val LEGACY_MANIFEST_FIELDS =
            setOf(
                "version",
                "batch_id",
                "created_at",
                "rejected_count",
                "rejected_indices",
                "complete",
                "items",
            )
        val MANIFEST_FIELDS = LEGACY_MANIFEST_FIELDS + "input_count"
        val ITEM_FIELDS = setOf("index", "path", "mime", "name", "size", "sha256")
    }

    private data class SharedInput(val index: Int, val uri: Uri)

    private data class RetainedItem(
        val index: Int,
        val path: String,
        val mime: String,
        val name: String,
        val size: Long,
        val sha256: String,
    )

    private val executor = Executors.newSingleThreadExecutor()
    private val inFlightBatches = mutableSetOf<String>()
    private var pendingPickResult: MethodChannel.Result? = null
    private var pickerResultProcessing = false
    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    fun acceptIntent(intent: Intent?) {
        if (intent == null || intent.action !in setOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) {
            return
        }
        val batchId = existingBatchId(intent) ?: UUID.randomUUID().toString().also {
            intent.putExtra(BATCH_ID_EXTRA, it)
        }
        val inputs = extractInputs(intent).take(MAX_INPUTS)
        val mimeHint = intent.type?.lowercase()
        synchronized(inFlightBatches) {
            if (!inFlightBatches.add(batchId)) return
        }
        executor.execute {
            val staged = try {
                stageBatch(batchId, inputs, mimeHint)
                true
            } catch (_: Exception) {
                false
            }
            synchronized(inFlightBatches) {
                inFlightBatches.remove(batchId)
            }
            activity.runOnUiThread {
                if (staged && activity.intent?.getStringExtra(BATCH_ID_EXTRA) == batchId) {
                    activity.intent = Intent(activity, MainActivity::class.java)
                }
                channel?.invokeMethod("shareEvent", null)
            }
        }
    }

    /** The marker is committed before launching the system picker and survives a recreated activity. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICKER_REQUEST) return false
        val batchId = pickerPreferences().getString(PENDING_PICKER_BATCH, null) ?: return true
        if (pickerResultProcessing) return true
        val result = pendingPickResult
        pendingPickResult = null
        if (resultCode == Activity.RESULT_CANCELED) {
            if (clearPickerMarker()) {
                result?.success(null)
            } else {
                result?.error("share_storage_unavailable", "The file picker could not be reset.", null)
            }
            return true
        }
        if (resultCode != Activity.RESULT_OK) {
            clearPickerMarker()
            result?.error("share_pick_failed", "The file picker did not complete.", null)
            return true
        }
        val inputs = SharePicker.selectedUris(data)
        if (inputs == null || inputs.isEmpty() || inputs.size > MAX_ITEMS || inputs.any { it.scheme != "content" }) {
            clearPickerMarker()
            result?.error("share_pick_failed", "Select between 1 and 20 supported files.", null)
            return true
        }
        pickerResultProcessing = true
        executor.execute {
            val staged = try {
                stageBatch(batchId, inputs.mapIndexed(::SharedInput), null)
                true
            } catch (_: Exception) {
                false
            }
            val cleared = clearPickerMarker()
            activity.runOnUiThread {
                pickerResultProcessing = false
                if (staged && cleared) {
                    result?.success(batchId)
                    channel?.invokeMethod("shareEvent", null)
                } else {
                    result?.error(
                        "share_storage_unavailable",
                        "Selected files could not be retained. Check the import queue.",
                        mapOf("retryable" to true),
                    )
                    // An interrupted batch may have durable receipts; the queue can recover them.
                    channel?.invokeMethod("shareEvent", null)
                }
            }
        }
        return true
    }

    private fun pickerPreferences() =
        activity.getSharedPreferences(PICKER_PREFERENCES, Activity.MODE_PRIVATE)

    private fun clearPickerMarker(): Boolean =
        pickerPreferences().edit().remove(PENDING_PICKER_BATCH).commit()

    private fun pick(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val source = arguments?.get("source") as? String
        val batchId = arguments?.get("batch_id") as? String
        if ((source != "files" && source != "photos") || batchId == null || !isCanonicalVersionFourUuid(batchId)) {
            result.error("bad_pick_request", "The file picker request is invalid.", null)
            return
        }
        if (pickerResultProcessing || pendingPickResult != null || pickerPreferences().contains(PENDING_PICKER_BATCH)) {
            result.error("share_pick_busy", "A file picker is already open.", null)
            return
        }
        val intent = if (source == "files") {
            SharePicker.filesIntent()
        } else {
            SharePicker.photosIntent(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
        }
        if (!pickerPreferences().edit().putString(PENDING_PICKER_BATCH, batchId).commit()) {
            result.error("share_storage_unavailable", "The file picker could not be started.", null)
            return
        }
        pendingPickResult = result
        try {
            activity.startActivityForResult(intent, PICKER_REQUEST)
        } catch (_: ActivityNotFoundException) {
            if (source != "photos" || intent.action != MediaStore.ACTION_PICK_IMAGES) {
                failPickerLaunch(result)
                return
            }
            try {
                activity.startActivityForResult(SharePicker.photosIntent(false), PICKER_REQUEST)
            } catch (_: Exception) {
                failPickerLaunch(result)
            }
        } catch (_: Exception) {
            failPickerLaunch(result)
        }
    }

    private fun failPickerLaunch(result: MethodChannel.Result) {
        pendingPickResult = null
        clearPickerMarker()
        result.error("share_pick_failed", "The file picker is unavailable.", null)
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPickResult = null
        pickerResultProcessing = false
        executor.shutdown()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(call, result)
            "pending" -> pending(result)
            "discard" -> discard(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pending(result: MethodChannel.Result) {
        executor.execute {
            try {
                val batches = loadPendingBatches()
                activity.runOnUiThread { result.success(batches) }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "share_storage_unavailable",
                        "Shared files could not be loaded.",
                        mapOf("retryable" to true),
                    )
                }
            }
        }
    }

    internal fun loadPendingBatches(): List<Map<String, Any?>> {
        val root = storeRoot().canonicalFile
        return root.listFiles()
            .orEmpty()
            .mapNotNull { entry ->
                if (Files.isSymbolicLink(entry.toPath()) || !entry.isDirectory) {
                    if (!entry.delete()) throw IOException("invalid share entry could not be removed")
                    null
                } else {
                    recoverBatch(root, entry)
                }
            }
            .sortedBy { it["created_at"] as Long }
    }

    private fun discard(call: MethodCall, result: MethodChannel.Result) {
        val batchId = call.argument<String>("batch_id")
        if (batchId == null || !isCanonicalVersionFourUuid(batchId)) {
            result.error("bad_batch_id", "The share batch id is invalid.", null)
            return
        }
        executor.execute {
            try {
                val root = storeRoot().canonicalFile
                val directory = File(root, batchId).canonicalFile
                if (directory.parentFile != root || (directory.exists() && !directory.deleteRecursively())) {
                    throw IOException("share batch could not be removed")
                }
                activity.runOnUiThread { result.success(null) }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "share_storage_unavailable",
                        "The share batch could not be discarded.",
                        mapOf("retryable" to true),
                    )
                }
            }
        }
    }

    private fun stageBatch(batchId: String, inputs: List<SharedInput>, mimeHint: String?) {
        val root = storeRoot()
        val directory = File(root, batchId)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IOException("share batch directory unavailable")
        }
        val existing = readManifest(directory)
        val createdAt = existing?.optLong("created_at")?.takeIf { it > 0 } ?: System.currentTimeMillis()
        val inputCount = existing?.getInt("input_count") ?: maxOf(1, inputs.size)
        val retained = existingItems(directory, existing)
        val rejectedIndexes = existingRejectedIndexes(existing)
        validateReceiptCoverage(inputCount, retained, rejectedIndexes, complete = existing?.getBoolean("complete") == true)
        if (existing?.getBoolean("complete") == true) return
        if (existing == null) {
            if (inputs.isEmpty()) {
                rejectedIndexes.add(0)
            } else {
                inputs.drop(MAX_ITEMS).mapTo(rejectedIndexes, SharedInput::index)
            }
            writeManifest(
                directory,
                batchId,
                createdAt,
                inputCount,
                retained,
                rejectedIndexes,
                complete = false,
            )
        }

        val retainedIndexes = retained.mapTo(mutableSetOf(), RetainedItem::index)
        for (input in inputs.take(MAX_ITEMS)) {
            if (input.index in retainedIndexes || input.index in rejectedIndexes) continue
            val mime = resolvedMime(input.uri, mimeHint)
            if (mime == null || mime !in SUPPORTED_MIME_TYPES) {
                rejectedIndexes.add(input.index)
                writeManifest(
                    directory,
                    batchId,
                    createdAt,
                    inputCount,
                    retained,
                    rejectedIndexes,
                    complete = false,
                )
                continue
            }
            try {
                val displayName = sanitizedShareName(displayName(input.uri), mime, input.index)
                val destination = File(directory, retainedSharePath(input.index))
                val item = copyAtomically(input, mime, displayName, destination)
                retained.add(item)
                retained.sortBy(RetainedItem::index)
                retainedIndexes.add(input.index)
            } catch (_: Exception) {
                rejectedIndexes.add(input.index)
            }
            writeManifest(
                directory,
                batchId,
                createdAt,
                inputCount,
                retained,
                rejectedIndexes,
                complete = false,
            )
        }
        val occupied = retained.mapTo(rejectedIndexes.toMutableSet(), RetainedItem::index)
        for (index in 0 until inputCount) {
            if (index !in occupied) rejectedIndexes.add(index)
        }
        writeManifest(
            directory,
            batchId,
            createdAt,
            inputCount,
            retained,
            rejectedIndexes,
            complete = true,
        )
    }

    private fun copyAtomically(
        input: SharedInput,
        mime: String,
        displayName: String,
        destination: File,
    ): RetainedItem {
        val part = File(destination.parentFile, destination.name + ".part")
        part.delete()
        val digest = MessageDigest.getInstance("SHA-256")
        val itemBudget = BoundedByteCounter(NativeIntakeLimits.MAX_DOCUMENT_BYTES)
        val header = ByteArray(4096)
        var headerSize = 0
        try {
            activity.contentResolver.openInputStream(input.uri).use { source ->
                if (source == null) throw IOException("share stream unavailable")
                FileOutputStream(part).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_SIZE)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        itemBudget.add(count)
                        if (headerSize < header.size) {
                            val copied = minOf(count, header.size - headerSize)
                            buffer.copyInto(header, headerSize, 0, copied)
                            headerSize += copied
                        }
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
        } catch (error: Exception) {
            part.delete()
            throw error
        }
        if (itemBudget.consumed == 0L) {
            part.delete()
            throw IOException("shared item is empty")
        }
        if (detectedMime(header, headerSize) != mime) {
            part.delete()
            throw IOException("shared item type did not match its contents")
        }
        if (!part.renameTo(destination)) {
            part.delete()
            throw IOException("share rename failed")
        }
        return RetainedItem(
            index = input.index,
            path = destination.name,
            mime = mime,
            name = displayName,
            size = itemBudget.consumed,
            sha256 = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) },
        )
    }

    private fun detectedMime(header: ByteArray, size: Int): String? {
        if (size >= 5 && header.copyOfRange(0, 5).contentEquals("%PDF-".toByteArray())) {
            return "application/pdf"
        }
        if (
            size >= 3 &&
                (header[0].toInt() and 0xff) == 0xff &&
                (header[1].toInt() and 0xff) == 0xd8 &&
                (header[2].toInt() and 0xff) == 0xff
        ) {
            return "image/jpeg"
        }
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
        if (size >= png.size && header.copyOfRange(0, png.size).contentEquals(png)) {
            return "image/png"
        }
        if (size < 16 || String(header, 4, 4, Charsets.US_ASCII) != "ftyp") return null
        val boxSize =
            ((header[0].toInt() and 0xff) shl 24) or
                ((header[1].toInt() and 0xff) shl 16) or
                ((header[2].toInt() and 0xff) shl 8) or
                (header[3].toInt() and 0xff)
        if (boxSize < 16 || boxSize > size || boxSize > header.size || (boxSize - 16) % 4 != 0) {
            return null
        }
        val brands = mutableSetOf<String>()
        for (offset in 8 until boxSize step 4) {
            if (offset == 12) continue
            brands.add(String(header, offset, 4, Charsets.US_ASCII).lowercase())
        }
        if (brands.any { it == "avif" || it == "avis" }) return null
        if (brands.any { it in setOf("heic", "heix", "hevc", "hevx") }) return "image/heic"
        if (brands.any { it == "mif1" || it == "msf1" }) return "image/heif"
        return null
    }

    private fun writeManifest(
        directory: File,
        batchId: String,
        createdAt: Long,
        inputCount: Int,
        items: List<RetainedItem>,
        rejectedIndexes: Set<Int>,
        complete: Boolean,
    ) {
        val sortedRejectedIndexes = rejectedIndexes.sorted()
        val json =
            JSONObject()
                .put("version", MANIFEST_VERSION)
                .put("batch_id", batchId)
                .put("created_at", createdAt)
                .put("input_count", inputCount)
                .put("rejected_count", sortedRejectedIndexes.size)
                .put("rejected_indices", JSONArray(sortedRejectedIndexes))
                .put("complete", complete)
                .put(
                    "items",
                    JSONArray(
                        items.map { item ->
                            JSONObject()
                                .put("index", item.index)
                                .put("path", item.path)
                                .put("mime", item.mime)
                                .put("name", item.name)
                                .put("size", item.size)
                                .put("sha256", item.sha256)
                        },
                    ),
                )
        val encoded = json.toString().toByteArray(Charsets.UTF_8)
        if (encoded.size > MAX_MANIFEST_BYTES) throw IOException("share manifest too large")
        val destination = File(directory, "manifest.json")
        val part = File(directory, "manifest.json.part")
        part.delete()
        FileOutputStream(part).use { output ->
            output.write(encoded)
            output.fd.sync()
        }
        if (!part.renameTo(destination)) {
            part.delete()
            throw IOException("share manifest rename failed")
        }
    }

    private fun existingRejectedIndexes(manifest: JSONObject?): MutableSet<Int> {
        val rawIndexes = manifest?.optJSONArray("rejected_indices") ?: return mutableSetOf()
        val indexes = mutableSetOf<Int>()
        for (position in 0 until rawIndexes.length()) {
            val index = rawIndexes.optInt(position, -1)
            if (index < 0 || !indexes.add(index)) {
                throw IOException("invalid rejected share receipt")
            }
        }
        if (indexes.size != manifest?.optInt("rejected_count", -1)) {
            throw IOException("invalid rejected share count")
        }
        return indexes
    }

    private fun readBatch(directory: File): Map<String, Any?>? {
        val manifest = readManifest(directory) ?: return null
        if (manifest.optInt("version") != MANIFEST_VERSION) return null
        val batchId = manifest.optString("batch_id")
        if (batchId != directory.name || !isCanonicalVersionFourUuid(batchId)) return null
        val createdAt = manifest.optLong("created_at")
        if (createdAt <= 0 || !manifest.has("complete")) return null
        val items = existingItems(directory, manifest)
        val rejectedIndexes = existingRejectedIndexes(manifest)
        validateReceiptCoverage(
            manifest.getInt("input_count"),
            items,
            rejectedIndexes,
            complete = manifest.getBoolean("complete"),
        )
        return mapOf(
            "batch_id" to batchId,
            "created_at" to createdAt,
            "rejected_count" to rejectedIndexes.size,
            "complete" to manifest.getBoolean("complete"),
            "items" to
                items.map { item ->
                    mapOf(
                        "index" to item.index,
                        "path" to File(directory, item.path).absolutePath,
                        "mime" to item.mime,
                        "name" to item.name,
                        "size" to item.size,
                        "sha256" to item.sha256,
                    )
                },
        )
    }

    private fun recoverBatch(root: File, directory: File): Map<String, Any?>? {
        val canonical = directory.canonicalFile
        if (canonical.parentFile != root || !isCanonicalVersionFourUuid(directory.name)) {
            if (canonical.parentFile == root && !directory.deleteRecursively()) {
                throw IOException("invalid share batch could not be removed")
            }
            return null
        }
        val manifest: JSONObject
        val items: MutableList<RetainedItem>
        val rejected: MutableSet<Int>
        var replacementInputCount = 1
        try {
            manifest = requireNotNull(readManifest(directory))
            replacementInputCount = manifest.getInt("input_count")
            items = existingItems(directory, manifest)
            rejected = existingRejectedIndexes(manifest)
            validateReceiptCoverage(
                manifest.getInt("input_count"),
                items,
                rejected,
                complete = manifest.getBoolean("complete"),
            )
        } catch (_: Exception) {
            return replaceWithRejectedBatch(root, directory, replacementInputCount)
        }
        if (manifest.getBoolean("complete")) return requireNotNull(readBatch(directory))

        val occupied = items.mapTo(rejected.toMutableSet(), RetainedItem::index)
        for (index in 0 until manifest.getInt("input_count")) {
            if (index !in occupied) rejected.add(index)
        }
        writeManifest(
            directory,
            directory.name,
            manifest.getLong("created_at"),
            manifest.getInt("input_count"),
            items,
            rejected,
            complete = true,
        )
        return requireNotNull(readBatch(directory))
    }

    private fun replaceWithRejectedBatch(
        root: File,
        directory: File,
        inputCount: Int,
    ): Map<String, Any?> {
        if (directory.canonicalFile.parentFile != root) {
            throw IOException("corrupt share batch escaped its store")
        }
        if (directory.exists() && !directory.deleteRecursively()) {
            throw IOException("corrupt share batch could not be terminalized")
        }
        if (!directory.mkdir()) throw IOException("share rejection directory unavailable")
        writeManifest(
            directory,
            directory.name,
            System.currentTimeMillis(),
            inputCount,
            emptyList(),
            (0 until inputCount).toSet(),
            complete = true,
        )
        return requireNotNull(readBatch(directory))
    }

    private fun existingItems(directory: File, manifest: JSONObject?): MutableList<RetainedItem> {
        if (manifest == null) return mutableListOf()
        val rawItems = manifest.optJSONArray("items") ?: return mutableListOf()
        val items = mutableListOf<RetainedItem>()
        var previousIndex = -1
        for (position in 0 until rawItems.length()) {
            val raw = rawItems.optJSONObject(position) ?: throw IOException("invalid share item")
            if (raw.keys().asSequence().toSet() != ITEM_FIELDS) {
                throw IOException("invalid share item fields")
            }
            val index = raw.optInt("index", -1)
            val relativePath = raw.optString("path")
            val mime = raw.optString("mime")
            val name = raw.optString("name")
            val size = raw.optLong("size", -1)
            val sha256 = raw.optString("sha256")
            if (
                index <= previousIndex ||
                    relativePath.isEmpty() ||
                    relativePath.contains('/') ||
                    relativePath.contains('\\') ||
                    mime !in SUPPORTED_MIME_TYPES ||
                    name.isEmpty() ||
                    size <= 0 ||
                    size > NativeIntakeLimits.MAX_DOCUMENT_BYTES ||
                    !sha256.matches(Regex("[0-9a-f]{64}"))
            ) {
                throw IOException("invalid share item")
            }
            val file = File(directory, relativePath)
            if (
                file.canonicalFile.parentFile != directory.canonicalFile ||
                    !file.isFile ||
                    file.length() != size ||
                    sha256(file) != sha256
            ) {
                throw IOException("retained share item changed")
            }
            items.add(RetainedItem(index, relativePath, mime, name, size, sha256))
            previousIndex = index
        }
        return items
    }

    private fun readManifest(directory: File): JSONObject? {
        val manifest = File(directory, "manifest.json")
        if (!manifest.isFile) return null
        if (manifest.length() <= 0 || manifest.length() > MAX_MANIFEST_BYTES) {
            throw IOException("invalid share manifest size")
        }
        val value = JSONObject(manifest.readText(Charsets.UTF_8))
        val fields = value.keys().asSequence().toSet()
        if (
            fields !in setOf(MANIFEST_FIELDS, LEGACY_MANIFEST_FIELDS) ||
                value.optInt("version", -1) != MANIFEST_VERSION ||
                value.optString("batch_id") != directory.name ||
                !isCanonicalVersionFourUuid(directory.name) ||
                value.optLong("created_at", -1) <= 0 ||
                value.optInt("rejected_count", -1) < 0 ||
                value.optJSONArray("rejected_indices") == null ||
                value.optJSONArray("items") == null ||
                value.get("complete") !is Boolean ||
                value.getJSONArray("items").length() > MAX_ITEMS
        ) {
            throw IOException("invalid share manifest")
        }
        if (fields == LEGACY_MANIFEST_FIELDS) {
            var maximumIndex = -1
            for (key in listOf("items", "rejected_indices")) {
                val values = value.getJSONArray(key)
                for (position in 0 until values.length()) {
                    val index = if (key == "items") {
                        values.optJSONObject(position)?.optInt("index", -1) ?: -1
                    } else {
                        values.optInt(position, -1)
                    }
                    maximumIndex = maxOf(maximumIndex, index)
                }
            }
            val interruptedTail = if (value.getBoolean("complete")) 0 else 1
            value.put("input_count", maxOf(1, maximumIndex + 1 + interruptedTail))
        }
        val inputCount = value.optInt("input_count", -1)
        if (inputCount <= 0 || inputCount > MAX_INPUTS) {
            throw IOException("invalid share input count")
        }
        return value
    }

    private fun validateReceiptCoverage(
        inputCount: Int,
        items: List<RetainedItem>,
        rejectedIndexes: Set<Int>,
        complete: Boolean,
    ) {
        val occupied = mutableSetOf<Int>()
        if (
            items.any { it.index !in 0 until inputCount || !occupied.add(it.index) } ||
                rejectedIndexes.any { it !in 0 until inputCount || !occupied.add(it) } ||
                complete && occupied.size != inputCount
        ) {
            throw IOException("invalid share receipt coverage")
        }
    }

    private fun storeRoot(): File {
        val root = File(activity.filesDir, STORE_NAME)
        if (!root.exists() && !root.mkdirs()) {
            throw IOException("share store unavailable")
        }
        return root
    }

    private fun resolvedMime(uri: Uri, hint: String?): String? {
        val resolved = activity.contentResolver.getType(uri)?.lowercase()
        if (resolved in SUPPORTED_MIME_TYPES) return resolved
        if (hint in SUPPORTED_MIME_TYPES) return hint
        val extension = displayName(uri)?.substringAfterLast('.', "")?.lowercase()
        return when (extension) {
            "pdf" -> "application/pdf"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            else -> resolved
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return@use null
                    cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))
                }
        } catch (_: Exception) {
            null
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(COPY_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun existingBatchId(intent: Intent): String? {
        return intent.getStringExtra(BATCH_ID_EXTRA)?.takeIf(::isCanonicalVersionFourUuid)
    }

    private fun isCanonicalVersionFourUuid(value: String): Boolean {
        return try {
            val parsed = UUID.fromString(value)
            parsed.version() == 4 && parsed.toString() == value
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun extractInputs(intent: Intent): List<SharedInput> {
        val uris =
            when (intent.action) {
                Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
                Intent.ACTION_SEND_MULTIPLE ->
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
                else -> emptyList()
            }.ifEmpty {
                val clip = intent.clipData ?: return@ifEmpty emptyList()
                (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
            }
        return uris.mapIndexed(::SharedInput)
    }
}

internal object SharePicker {
    private val imageMimeTypes = arrayOf("image/jpeg", "image/png", "image/heic", "image/heif")

    fun filesIntent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "*/*"
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/pdf", *imageMimeTypes))
        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    fun photosIntent(systemPickerAvailable: Boolean): Intent =
        if (systemPickerAvailable) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 20)
            }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                putExtra(Intent.EXTRA_MIME_TYPES, imageMimeTypes)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }

    fun selectedUris(data: Intent?): List<Uri>? {
        if (data == null) return emptyList()
        val clip = data.clipData
        return if (clip != null) {
            (0 until clip.itemCount).map { clip.getItemAt(it).uri ?: return null }
        } else {
            listOfNotNull(data.data)
        }
    }
}

internal fun sanitizedShareName(rawName: String?, mime: String, index: Int): String {
    val raw = rawName?.substringAfterLast('/')?.substringAfterLast('\\').orEmpty()
    val safe = raw.map { character ->
        when {
            character.isLetterOrDigit() -> character
            character in setOf(' ', '.', '-', '_') -> character
            else -> '_'
        }
    }.joinToString("").trim(' ', '.')
    val extension =
        when (mime) {
            "application/pdf" -> "pdf"
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/heic" -> "heic"
            "image/heif" -> "heif"
            else -> "bin"
        }
    val suffix = ".$extension"
    val rawStem = safe.substringBeforeLast('.', safe).ifEmpty { "shared-${index + 1}" }
    val maximumStemBytes = 255 - suffix.toByteArray(Charsets.UTF_8).size
    val stem = StringBuilder()
    var byteCount = 0
    for (character in rawStem) {
        val encoded = character.toString().toByteArray(Charsets.UTF_8)
        if (byteCount + encoded.size > maximumStemBytes) break
        stem.append(character)
        byteCount += encoded.size
    }
    return (stem.toString().trimEnd(' ', '.').ifEmpty { "shared-${index + 1}" }) + suffix
}

internal fun retainedSharePath(index: Int): String =
    "item-${index.toString().padStart(3, '0')}.payload"
