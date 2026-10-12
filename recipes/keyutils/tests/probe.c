#include <errno.h>
#include <stdio.h>
#include <string.h>

#include <keyutils.h>
int main(void)
{
        if (!strstr(keyutils_version_string, "1.6.3"))
                return 1;
        /* Invalid IDs exercise the syscall wrapper without altering any keyring. */
        errno = 0;
        if (keyctl_read(0, NULL, 0) != -1 || errno == 0)
                return 2;
        puts("keyutils version and syscall error propagation: OK");
        return 0;
}
