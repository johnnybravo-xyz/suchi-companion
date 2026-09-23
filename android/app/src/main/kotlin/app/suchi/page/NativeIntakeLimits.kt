package app.suchi.page

import java.io.IOException

internal object NativeIntakeLimits {
    const val MAX_DOCUMENT_BYTES = 64L * 1024 * 1024
    const val MAX_CAPTURE_WORKING_BYTES = 2 * MAX_DOCUMENT_BYTES
    const val MAX_CAPTURE_PAGES = 20
    const val MAX_CAPTURE_PAGE_BYTES = 16L * 1024 * 1024
    const val CAPTURE_LIMIT_MESSAGE =
        "Scans are limited to 20 pages, 16 MiB per page, and 64 MiB total."
}

internal class IntakeLimitExceededException : IOException("native intake limit exceeded")

internal class BoundedByteCounter(private val maximum: Long) {
    var consumed: Long = 0
        private set

    fun add(count: Int) {
        if (count < 0 || consumed > maximum - count) {
            throw IntakeLimitExceededException()
        }
        consumed += count
    }
}
