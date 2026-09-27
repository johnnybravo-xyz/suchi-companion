package page.suchi.companion

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import androidx.core.content.FileProvider
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class NativeAdapterInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val targetContext = instrumentation.targetContext
    private val pickerPreferences by lazy {
        targetContext.getSharedPreferences("suchi-share-picker", Activity.MODE_PRIVATE)
    }
    private val shareRoot by lazy { File(targetContext.filesDir, "suchi-share-imports") }

    @Before
    fun clearShareStore() {
        shareRoot.deleteRecursively()
        assertTrue(pickerPreferences.edit().clear().commit())
    }

    @After
    fun removeShareStore() {
        shareRoot.deleteRecursively()
        assertTrue(pickerPreferences.edit().clear().commit())
    }

    @Test
    fun writableStoragePreservesReserveAfterWrite() {
        val reserve = WritableStorage.MINIMUM_FREE_BYTES

        assertTrue(WritableStorage.canWrite(reserve + 1_024, 1_024))
        assertFalse(WritableStorage.canWrite(reserve + 1_024, 1_025))
    }

    @Test
    fun nativeResultSerializationPreservesOrderAndCancellation() {
        val completed =
            ScanResultPayload.completed(
                pdfPath = "/capture/document.pdf",
                pageCount = 3,
                pagePaths = listOf("/capture/page-000.jpg", "/capture/page-001.jpg"),
            )
        @Suppress("UNCHECKED_CAST")
        val pages = completed["pages"] as List<Map<String, String>>

        assertEquals(false, completed["cancelled"])
        assertEquals("/capture/document.pdf", completed["pdf_path"])
        assertEquals(3, completed["page_count"])
        assertEquals(
            listOf("/capture/page-000.jpg", "/capture/page-001.jpg"),
            pages.map { it.getValue("path") },
        )

        val cancelled = ScanResultPayload.cancelled()
        assertEquals(true, cancelled["cancelled"])
        assertNull(cancelled["pdf_path"])
        assertEquals(0, cancelled["page_count"])
        assertTrue((cancelled["pages"] as List<*>).isEmpty())

        val unavailable =
            ScanResultPayload.recognitionUnavailable(
                listOf("/capture/page-000.jpg", "/capture/page-001.jpg"),
            )
        assertEquals(
            listOf("/capture/page-000.jpg", "/capture/page-001.jpg"),
            unavailable.map { it["path"] },
        )
        assertTrue(unavailable.all { it["error_code"] == "recognition_unavailable" })
        assertTrue(unavailable.all { it["confidence"] == null })
    }

    @Test
    fun photoCaptureUsesFullSizeOutputAndOnlyTemporaryUriGrants() {
        val uri = Uri.parse("content://page.suchi.companion.photo-capture/photo/pending.jpg")
        val intent = PhotoCapture.intent(uri)
        assertEquals(MediaStore.ACTION_IMAGE_CAPTURE, intent.action)
        assertEquals(uri, intent.getParcelableExtra<Uri>(MediaStore.EXTRA_OUTPUT))
        assertEquals(uri, intent.clipData?.getItemAt(0)?.uri)
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION, intent.flags)
        assertFalse(intent.hasExtra("data"))
        assertThrows(IllegalArgumentException::class.java) {
            FileProvider.getUriForFile(
                targetContext,
                "${targetContext.packageName}.photo-capture",
                File(targetContext.filesDir, "suchi-scanner-captures/private.jpg"),
            )
        }
    }

    @Test
    fun documentHandoffGrantsOnlyReadAccessToOneFile() {
        val uri = Uri.parse("content://page.suchi.companion.document-exports/documents/document-test/document-91.pdf")
        for (share in listOf(true, false)) {
            val intent = DocumentExport.intent(uri, "application/pdf", share)
            assertEquals(if (share) Intent.ACTION_SEND else Intent.ACTION_VIEW, intent.action)
            assertEquals("application/pdf", intent.type)
            assertEquals(uri, intent.clipData?.getItemAt(0)?.uri)
            assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, intent.flags)
            if (share) assertEquals(uri, intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            else assertEquals(uri, intent.data)
        }
    }

    @Test
    fun documentHandoffAcceptsOnlyExactExportAndOfflinePayloads() {
        val base = File(targetContext.cacheDir, "document-export-test-${UUID.randomUUID()}")
        val exportRoot = File(base, "suchi-document-exports")
        val offlineRoot = File(base, "suchi-offline-documents")
        val roots = listOf(
            DocumentRoot(exportRoot, "document-"),
            DocumentRoot(offlineRoot, "offline-"),
        )
        try {
            val exportOperation = File(exportRoot, "document-test").apply { mkdirs() }
            val exported = File(exportOperation, "document-91.pdf").apply { writeText("%PDF-test") }
            assertEquals(exported.canonicalFile, DocumentExport.file(roots, exported.path))

            val offlineOperation = File(
                offlineRoot,
                "offline-00000000-0000-4000-8000-000000000001",
            ).apply { mkdirs() }
            val offline = File(offlineOperation, "document-91.pdf").apply { writeText("%PDF-offline") }
            assertEquals(offline.canonicalFile, DocumentExport.file(roots, offline.path))
            val manifest = File(offlineOperation, "manifest.json").apply { writeText("private metadata") }
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, manifest.path)
            }
            val uncommitted = File(offlineRoot, "offline-test/document-91.pdf").apply {
                parentFile?.mkdirs()
                writeText("%PDF-uncommitted")
            }
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, uncommitted.path)
            }

            val outside = File(base, "private.pdf").apply { writeText("private") }
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, outside.path)
            }
            val nested = File(exportOperation, "nested/document.pdf").apply {
                parentFile?.mkdirs()
                writeText("%PDF-nested")
            }
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, nested.path)
            }
            val staging = File(offlineRoot, "offline-test.part/document.pdf").apply {
                parentFile?.mkdirs()
                writeText("%PDF-staging")
            }
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, staging.path)
            }
            val link = File(exportOperation, "linked.pdf")
            android.system.Os.symlink(offline.path, link.path)
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, link.path)
            }
            val outsideDirectory = File(base, "outside-directory").apply { mkdirs() }
            val outsidePayload = File(outsideDirectory, "document.pdf").apply { writeText("%PDF-outside") }
            val linkedOperation = File(offlineRoot, "offline-linked")
            android.system.Os.symlink(outsideDirectory.path, linkedOperation.path)
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, File(linkedOperation, outsidePayload.name).path)
            }
            val oversized = File(offlineOperation, "oversized.pdf")
            RandomAccessFile(oversized, "rw").use {
                it.setLength(64L * 1024 * 1024 + 1)
            }
            assertThrows(IllegalArgumentException::class.java) {
                DocumentExport.file(roots, oversized.path)
            }
        } finally {
            base.deleteRecursively()
        }
    }

    @Test
    fun savedPayloadOpensThroughTheConfiguredFileProviderWithoutCopying() {
        val offlineRoot = File(targetContext.filesDir, "suchi-offline-documents")
        val operation = File(offlineRoot, "offline-${UUID.randomUUID()}")
        assertTrue(operation.mkdirs())
        try {
            val payload = File(operation, "document-91.pdf").apply {
                writeText("%PDF-saved")
            }
            val accepted = DocumentExport.file(
                listOf(DocumentRoot(offlineRoot, "offline-")),
                payload.path,
            )
            assertEquals(payload.canonicalFile, accepted)
            val uri = FileProvider.getUriForFile(
                targetContext,
                "${targetContext.packageName}.document-exports",
                accepted,
            )
            assertEquals("content", uri.scheme)
            assertEquals(
                "%PDF-saved",
                targetContext.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() },
            )
            assertTrue(payload.isFile)
        } finally {
            operation.deleteRecursively()
        }
    }

    @Test
    fun sharedFilenameIsBoundedByUtf8Bytes() {
        val name = sanitizedShareName("文".repeat(200) + ".pdf", "application/pdf", 0)

        assertTrue(name.toByteArray(Charsets.UTF_8).size <= 255)
        assertTrue(name.endsWith(".pdf"))
        assertTrue(sanitizedShareName("capture", "image/heic", 1).endsWith(".heic"))
        assertTrue(sanitizedShareName("capture", "image/heif", 2).endsWith(".heif"))
        val retainedPath = retainedSharePath(0)
        assertTrue(retainedPath.toByteArray(Charsets.UTF_8).size <= 255)
        assertTrue("$retainedPath.part".toByteArray(Charsets.UTF_8).size <= 255)
    }

    @Test
    fun nativeByteBudgetRejectsBeforeWritingPastItsLimit() {
        val budget = BoundedByteCounter(8)
        budget.add(6)

        try {
            budget.add(3)
            throw AssertionError("Expected native intake limit failure")
        } catch (_: IntakeLimitExceededException) {
            assertEquals(6L, budget.consumed)
        }
    }

    @Test
    fun shareIntentRetainsGrantedUrisOnceAndClearsLaunchIntent() {
        val intent = shareIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertEquals(2, intent.clipData?.itemCount)
        instrumentation.context.startActivity(intent)
        val activity = waitForActivity()
        try {
            val manifestFile = waitForManifest()
            val manifest = JSONObject(manifestFile.readText())
            val batchId = manifest.getString("batch_id")
            val parsedBatchId = UUID.fromString(batchId)
            val items = manifest.getJSONArray("items")

            assertEquals(4, parsedBatchId.version())
            assertEquals(parsedBatchId.toString(), batchId)
            assertEquals(2, items.length())
            assertEquals("duplicate.pdf", items.getJSONObject(0).getString("name"))
            assertEquals("duplicate.pdf", items.getJSONObject(1).getString("name"))
            assertNotEquals(
                items.getJSONObject(0).getString("path"),
                items.getJSONObject(1).getString("path"),
            )
            assertNotEquals(
                items.getJSONObject(0).getString("sha256"),
                items.getJSONObject(1).getString("sha256"),
            )
            assertTrue(File(manifestFile.parentFile, items.getJSONObject(0).getString("path")).isFile)
            assertTrue(File(manifestFile.parentFile, items.getJSONObject(1).getString("path")).isFile)
            assertLaunchIntentCleared(activity)

            instrumentation.context.startActivity(
                shareIntent(batchId).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            SystemClock.sleep(300)
            assertEquals(1, shareRoot.listFiles().orEmpty().filter(File::isDirectory).size)
            assertLaunchIntentCleared(activity)
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }

    @Test
    fun pendingTerminalizesInterruptedAndCorruptShareBatches() {
        instrumentation.context.startActivity(
            Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        val activity = waitForActivity()
        val interruptedId = UUID.randomUUID().toString()
        val corruptId = UUID.randomUUID().toString()
        try {
            val interrupted = File(shareRoot, interruptedId)
            assertTrue(interrupted.mkdirs())
            File(interrupted, "manifest.json").writeText(
                JSONObject()
                    .put("version", 1)
                    .put("batch_id", interruptedId)
                    .put("created_at", System.currentTimeMillis())
                    .put("input_count", 3)
                    .put("rejected_count", 0)
                    .put("rejected_indices", JSONArray())
                    .put("complete", false)
                    .put("items", JSONArray())
                    .toString(),
            )
            val corrupt = File(shareRoot, corruptId)
            assertTrue(corrupt.mkdirs())
            File(corrupt, "manifest.json").writeText("{not-json")

            val intake = ShareChannel(activity)
            val batches = try {
                intake.loadPendingBatches()
            } finally {
                intake.close()
            }

            assertEquals(setOf(interruptedId, corruptId), batches.map { it["batch_id"] }.toSet())
            assertTrue(batches.all { it["complete"] == true })
            assertEquals(
                3,
                batches.single { it["batch_id"] == interruptedId }["rejected_count"],
            )
            assertEquals(
                1,
                batches.single { it["batch_id"] == corruptId }["rejected_count"],
            )
            assertTrue(batches.all { (it["items"] as List<*>).isEmpty() })
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }

    @Test
    fun invalidSharedItemsAreRejectedWithoutLosingValidItems() {
        val intent = shareIntent(segments = listOf("first", "empty", "spoof"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        instrumentation.context.startActivity(intent)
        val activity = waitForActivity()
        try {
            val manifest = JSONObject(waitForManifest().readText())

            assertEquals(1, manifest.getJSONArray("items").length())
            assertEquals(2, manifest.getInt("rejected_count"))
            assertTrue(manifest.getBoolean("complete"))
            assertLaunchIntentCleared(activity)
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }

    @Test
    fun pickerIntentsRequestOnlySupportedDocumentsAndStillImages() {
        val files = SharePicker.filesIntent()
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, files.action)
        assertTrue(files.hasCategory(Intent.CATEGORY_OPENABLE))
        assertEquals("*/*", files.type)
        assertTrue(files.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false))
        assertEquals(
            setOf("application/pdf", "image/jpeg", "image/png", "image/heic", "image/heif"),
            files.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.toSet(),
        )

        val fallback = SharePicker.photosIntent(false)
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, fallback.action)
        assertEquals("image/*", fallback.type)
        assertTrue(fallback.hasCategory(Intent.CATEGORY_OPENABLE))
        assertTrue(fallback.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false))
        assertEquals(
            setOf("image/jpeg", "image/png", "image/heic", "image/heif"),
            fallback.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.toSet(),
        )

        val system = SharePicker.photosIntent(true)
        assertEquals(MediaStore.ACTION_PICK_IMAGES, system.action)
        assertEquals("image/*", system.type)
        assertEquals(20, system.getIntExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 0))
    }

    @Test
    fun coldStartClearsAnAbandonedPickerClaim() {
        instrumentation.context.startActivity(
            Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        val activity = waitForActivity()
        try {
            assertTrue(
                markPicker(
                    UUID.randomUUID().toString(),
                    System.currentTimeMillis() - (24 * 60 * 60 * 1000L),
                ),
            )
            val recovered = ShareChannel(activity)
            recovered.close()
            assertFalse(pickerPreferences.contains("pending_batch_id"))
            assertFalse(pickerPreferences.contains("pending_created_at_ms"))
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }

    @Test
    fun recreatedPickerStagesOnlyItsClaimedBatchAndCancellationLeavesNoBatch() {
        instrumentation.context.startActivity(
            Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        val activity = waitForActivity()
        try {
            val canceledId = UUID.randomUUID().toString()
            assertTrue(markPicker(canceledId))
            val canceled = ShareChannel(activity)
            try {
                instrumentation.runOnMainSync {
                    assertTrue(canceled.onActivityResult(4721, Activity.RESULT_CANCELED, null))
                }
            } finally {
                canceled.close()
            }
            assertFalse(pickerPreferences.contains("pending_batch_id"))
            assertFalse(pickerPreferences.contains("pending_created_at_ms"))
            assertFalse(File(shareRoot, canceledId).exists())

            val retainedId = UUID.randomUUID().toString()
            assertTrue(markPicker(retainedId))
            val restored = ShareChannel(activity)
            try {
                val first = Uri.parse("content://page.suchi.companion.test.share/first")
                val empty = Uri.parse("content://page.suchi.companion.test.share/empty")
                val clip = ClipData.newUri(targetContext.contentResolver, "first", first)
                clip.addItem(ClipData.Item(empty))
                instrumentation.runOnMainSync {
                    assertTrue(
                        restored.onActivityResult(
                            4721,
                            Activity.RESULT_OK,
                            Intent().apply { clipData = clip },
                        ),
                    )
                }
                waitUntil {
                    File(shareRoot, retainedId).resolve("manifest.json")
                        .takeIf(File::isFile)
                        ?.let { JSONObject(it.readText()).optBoolean("complete") } == true &&
                        !pickerPreferences.contains("pending_batch_id") &&
                        !pickerPreferences.contains("pending_created_at_ms")
                }
                val manifest = JSONObject(File(shareRoot, "$retainedId/manifest.json").readText())
                assertEquals(retainedId, manifest.getString("batch_id"))
                assertEquals(2, manifest.getInt("input_count"))
                assertEquals(1, manifest.getJSONArray("items").length())
                assertEquals(1, manifest.getInt("rejected_count"))
            } finally {
                restored.close()
            }
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }

    @Test
    fun pickerRejectsMoreThanTwentySelectionsWithoutMakingAReceipt() {
        instrumentation.context.startActivity(
            Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        val activity = waitForActivity()
        val batchId = UUID.randomUUID().toString()
        try {
            assertTrue(markPicker(batchId))
            val uri = Uri.parse("content://page.suchi.companion.test.share/first")
            val clip = ClipData.newUri(targetContext.contentResolver, "first", uri)
            repeat(20) { clip.addItem(ClipData.Item(uri)) }
            val intake = ShareChannel(activity)
            try {
                instrumentation.runOnMainSync {
                    assertTrue(intake.onActivityResult(4721, Activity.RESULT_OK, Intent().apply { clipData = clip }))
                }
            } finally {
                intake.close()
            }
            assertFalse(pickerPreferences.contains("pending_batch_id"))
            assertFalse(pickerPreferences.contains("pending_created_at_ms"))
            assertFalse(File(shareRoot, batchId).exists())
        } finally {
            instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        }
    }

    private fun markPicker(
        batchId: String,
        createdAtMs: Long = System.currentTimeMillis(),
    ): Boolean =
        pickerPreferences
            .edit()
            .putString("pending_batch_id", batchId)
            .putLong("pending_created_at_ms", createdAtMs)
            .commit()

    private fun shareIntent(
        batchId: String? = null,
        segments: List<String> = listOf("first", "second"),
    ): Intent {
        val uris = segments.map { Uri.parse("content://page.suchi.companion.test.share/$it") }
        val clip = ClipData.newUri(instrumentation.context.contentResolver, "first", uris.first())
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        return Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            setClass(targetContext, MainActivity::class.java)
            type = "application/pdf"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
            clipData = clip
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (batchId != null) putExtra("page.suchi.companion.share.BATCH_ID", batchId)
        }
    }

    private fun waitForManifest(): File {
        var result: File? = null
        waitUntil {
            result =
                shareRoot.listFiles().orEmpty()
                    .filter(File::isDirectory)
                    .singleOrNull()
                    ?.resolve("manifest.json")
                    ?.takeIf(File::isFile)
            result?.let { JSONObject(it.readText()).optBoolean("complete") } == true
        }
        return requireNotNull(result)
    }

    private fun waitForActivity(): MainActivity {
        var result: MainActivity? = null
        waitUntil {
            instrumentation.runOnMainSync {
                result =
                    ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED)
                        .filterIsInstance<MainActivity>()
                        .firstOrNull()
            }
            result != null
        }
        return requireNotNull(result)
    }

    private fun assertLaunchIntentCleared(activity: MainActivity) {
        waitUntil {
            var cleared = false
            instrumentation.runOnMainSync {
                cleared = activity.intent.action == null && !activity.intent.hasExtra(Intent.EXTRA_STREAM)
            }
            cleared
        }
        instrumentation.runOnMainSync {
            assertNull(activity.intent.action)
            assertFalse(activity.intent.hasExtra("page.suchi.companion.share.BATCH_ID"))
        }
    }

    private fun waitUntil(condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 10_000
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            SystemClock.sleep(40)
        }
        throw AssertionError("Timed out waiting for native adapter state")
    }
}
