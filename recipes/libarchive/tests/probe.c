#include <stdio.h>
#include <string.h>

#include <archive.h>
#include <archive_entry.h>

int main(void)
{
        char buffer[65536], output[64];
        const char payload[] = "devkit LZO-compressed tar archive";
        size_t size = 0;
        struct archive *writer = archive_write_new(), *reader;
        struct archive_entry *entry = archive_entry_new();
        if (!writer || !entry)
                return 1;
        /* ARCHIVE_OK requires native support; a fallback to external lzop warns. */
        if (archive_write_add_filter_lzop(writer) != ARCHIVE_OK)
                return 2;
        if (archive_write_set_format_ustar(writer) != ARCHIVE_OK)
                return 3;
        if (archive_write_open_memory(writer, buffer, sizeof(buffer), &size) !=
            ARCHIVE_OK)
                return 4;
        archive_entry_set_pathname(entry, "message.txt");
        archive_entry_set_filetype(entry, AE_IFREG);
        archive_entry_set_perm(entry, 0644);
        archive_entry_set_size(entry, sizeof(payload));
        if (archive_write_header(writer, entry) != ARCHIVE_OK)
                return 5;
        if (archive_write_data(writer, payload, sizeof(payload)) !=
            sizeof(payload))
                return 6;
        if (archive_write_close(writer) != ARCHIVE_OK)
                return 7;
        archive_write_free(writer);
        archive_entry_free(entry);
        reader = archive_read_new();
        archive_read_support_filter_all(reader);
        archive_read_support_format_all(reader);
        if (archive_read_open_memory(reader, buffer, size) != ARCHIVE_OK)
                return 8;
        if (archive_read_next_header(reader, &entry) != ARCHIVE_OK)
                return 9;
        if (archive_filter_code(reader, 0) != ARCHIVE_FILTER_LZOP)
                return 10;
        if (archive_read_data(reader, output, sizeof(output)) !=
            sizeof(payload))
                return 11;
        if (memcmp(payload, output, sizeof(payload)))
                return 12;
        archive_read_free(reader);
        puts("native LZO-compressed tar write/read roundtrip: OK");
        return 0;
}
