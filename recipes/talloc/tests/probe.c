#include <string.h>

#include <talloc.h>
int main(void)
{
        char *s = talloc_strdup(0, "devkit");
        int ok = s && !strcmp(s, "devkit");
        talloc_free(s);
        return !ok;
}
