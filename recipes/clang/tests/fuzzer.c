#include <stddef.h>
#include <stdint.h>
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
        if (size) {
                volatile uint8_t value = data[0];
                (void)value;
        }
        return 0;
}
