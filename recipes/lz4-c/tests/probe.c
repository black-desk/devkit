#include <stdio.h>
#include <string.h>

#include <lz4.h>
int main(void)
{
        const char input[] = "devkit LZ4 compression roundtrip";
        char compressed[256], output[sizeof(input)];
        int size = LZ4_compress_default(input, compressed, sizeof(input),
                                        sizeof(compressed));
        if (size <= 0)
                return 1;
        if (LZ4_decompress_safe(compressed, output, size, sizeof(output)) !=
            sizeof(input))
                return 2;
        if (memcmp(input, output, sizeof(input)))
                return 3;
        puts("LZ4 compression/decompression: OK");
        return 0;
}
