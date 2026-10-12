#include <stdio.h>

#include <pcre2.h>

int main(void)
{
        const PCRE2_UCHAR pattern[] = { 'd', 'e', 'v', 'k', 'i', 't', 0 };
        int error;
        PCRE2_SIZE offset;
        pcre2_code *code = pcre2_compile(pattern, PCRE2_ZERO_TERMINATED, 0,
                                         &error, &offset, NULL);
        if (!code)
                return 1;
        uint32_t enabled = 0;
        if (pcre2_config(PCRE2_CONFIG_UNICODE, &enabled) != 0 || enabled != 1 ||
            pcre2_jit_compile(code, PCRE2_JIT_COMPLETE) != 0)
                return 2;
        pcre2_match_data *data =
                pcre2_match_data_create_from_pattern(code, NULL);
        if (!data)
                return 3;
        int matched = pcre2_match(code, pattern, 6, 0, 0, data, NULL);
        pcre2_match_data_free(data);
        pcre2_code_free(code);
        printf("pcre2-%d: Unicode, JIT and matching verified\n",
               PCRE2_CODE_UNIT_WIDTH);
        return matched == 1 ? 0 : 4;
}
