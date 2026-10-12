#include <stdio.h>
#include <string.h>

#include <libssh2.h>
int main(void)
{
        LIBSSH2_SESSION *session;
        const char **methods;
        int count, i, compression = 0;
        if (strcmp(libssh2_version(0), "1.11.1") || libssh2_init(0))
                return 1;
        session = libssh2_session_init();
        if (!session)
                return 2;
        /* Compression is opt-in per session, even when compiled into the library. */
        if (libssh2_session_flag(session, LIBSSH2_FLAG_COMPRESS, 1))
                return 4;
        count = libssh2_session_supported_algs(session, LIBSSH2_METHOD_COMP_CS,
                                               &methods);
        for (i = 0; i < count; ++i)
                if (!strcmp(methods[i], "zlib"))
                        compression = 1;
        if (count <= 0 || !compression)
                return 3;
        libssh2_free(session, (void *)methods);
        libssh2_session_free(session);
        libssh2_exit();
        puts("libssh2 initialization and zlib compression support: OK");
        return 0;
}
