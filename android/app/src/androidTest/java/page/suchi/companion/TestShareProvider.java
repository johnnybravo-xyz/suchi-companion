package page.suchi.companion;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public final class TestShareProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return "application/pdf";
    }

    @Override
    public Cursor query(
            Uri uri,
            String[] projection,
            String selection,
            String[] selectionArgs,
            String sortOrder) {
        String[] columns = projection == null
                ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}
                : projection;
        MatrixCursor cursor = new MatrixCursor(columns);
        Object[] row = new Object[columns.length];
        for (int index = 0; index < columns.length; index++) {
            if (OpenableColumns.DISPLAY_NAME.equals(columns[index])) {
                row[index] = "duplicate.pdf";
            } else if (OpenableColumns.SIZE.equals(columns[index])) {
                row[index] = (long) bytes(uri).length;
            }
        }
        cursor.addRow(row);
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) {
            throw new FileNotFoundException("read-only fixture");
        }
        try {
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
            Thread writer = new Thread(() -> {
                try (ParcelFileDescriptor.AutoCloseOutputStream output =
                             new ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])) {
                    output.write(bytes(uri));
                } catch (IOException ignored) {
                    // A closed reader means the test no longer needs the fixture.
                }
            }, "suchi-test-share-provider");
            writer.start();
            return pipe[0];
        } catch (IOException error) {
            throw new FileNotFoundException(error.getMessage());
        }
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }

    private byte[] bytes(Uri uri) {
        String value;
        if ("first".equals(uri.getLastPathSegment())) {
            value = "%PDF-1.4\nfirst fixture\n";
        } else if ("second".equals(uri.getLastPathSegment())) {
            value = "%PDF-1.4\nsecond fixture\n";
        } else if ("empty".equals(uri.getLastPathSegment())) {
            value = "";
        } else if ("spoof".equals(uri.getLastPathSegment())) {
            return new byte[]{
                    (byte) 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
                    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
            };
        } else {
            throw new IllegalArgumentException("unknown fixture");
        }
        return value.getBytes(StandardCharsets.UTF_8);
    }
}
