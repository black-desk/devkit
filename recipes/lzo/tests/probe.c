#include <stdio.h>
#include <string.h>

#include <lzo/lzo1x.h>
int main(void)
{
        const unsigned char input[] = "devkit LZO1X compression roundtrip";
        unsigned char compressed[256], output[sizeof(input)];
        lzo_align_t workspace[(LZO1X_1_MEM_COMPRESS + sizeof(lzo_align_t) - 1) /
                              sizeof(lzo_align_t)];
        lzo_uint compressed_size = sizeof(compressed),
                 output_size = sizeof(output);
        if (lzo_init() != LZO_E_OK)
                return 1;
        if (lzo1x_1_compress(input, sizeof(input), compressed, &compressed_size,
                             workspace) != LZO_E_OK)
                return 2;
        if (lzo1x_decompress_safe(compressed, compressed_size, output,
                                  &output_size, NULL) != LZO_E_OK)
                return 3;
        if (output_size != sizeof(input) ||
            memcmp(input, output, sizeof(input)))
                return 4;
        puts("LZO1X compression/decompression: OK");
        return 0;
}
