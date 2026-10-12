#include <stdio.h>
#include <string.h>

#include <libpsl.h>
int main(void)
{
        const psl_ctx_t *ctx = psl_builtin();
        const char *domain;
        char *lower = NULL;
        if (!ctx || !psl_is_public_suffix(ctx, "co.uk"))
                return 1;
        domain = psl_registrable_domain(ctx, "www.example.co.uk");
        if (!domain || strcmp(domain, "example.co.uk"))
                return 2;
        if (psl_is_cookie_domain_acceptable(ctx, "www.example.co.uk", "co.uk"))
                return 3;
        if (psl_str_to_utf8lower("BÜCHER.DE", "utf-8", NULL, &lower) !=
                    PSL_SUCCESS ||
            !lower || strcmp(lower, "bücher.de"))
                return 4;
        psl_free_string(lower);
        puts("libpsl suffix data, cookie boundaries and ICU lowercase: OK");
        return 0;
}
