#include <stdio.h>
#include <string.h>

#include <crypt.h>

int main(void)
{
        struct crypt_data data = { 0 };
        const char *hash = crypt_r("devkit", "$6$devkit$", &data);
        if (!hash || strncmp(hash, "$6$devkit$", 10) != 0) {
                return 1;
        }
        char saved[CRYPT_OUTPUT_SIZE];
        snprintf(saved, sizeof(saved), "%s", hash);
        hash = crypt_r("devkit", saved, &data);
        if (!hash || strcmp(saved, hash) != 0) {
                return 1;
        }
        puts("libxcrypt crypt_r: OK");
        return 0;
}
