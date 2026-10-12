#include <stdio.h>
#include <string.h>

#include <krb5.h>
int main(void)
{
        krb5_context ctx;
        krb5_principal principal;
        char *name;
        if (krb5_init_context(&ctx))
                return 1;
        if (krb5_parse_name(ctx, "bootstrap@EXAMPLE.INVALID", &principal))
                return 2;
        if (krb5_unparse_name(ctx, principal, &name))
                return 3;
        if (strcmp(name, "bootstrap@EXAMPLE.INVALID"))
                return 4;
        krb5_free_unparsed_name(ctx, name);
        krb5_free_principal(ctx, principal);
        krb5_free_context(ctx);
        puts("Kerberos context and principal roundtrip: OK");
        return 0;
}
