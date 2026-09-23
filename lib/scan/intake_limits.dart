const maximumDocumentBytes = 64 * 1024 * 1024;
const maximumCapturePages = 20;
const maximumCapturePageBytes = 16 * 1024 * 1024;
const maximumCaptureSourceBytes = 64 * 1024 * 1024;
const captureLimitMessage =
    'Scans are limited to 20 pages, 16 MiB per page, and 64 MiB total.';
