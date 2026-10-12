#include <stdio.h>
#include <string.h>

#include <ares.h>
static int called;
static void resolved(void *arg, int status, int timeouts,
                     struct ares_addrinfo *result)
{
        (void)arg;
        (void)timeouts;
        if (status == ARES_SUCCESS && result && result->nodes)
                called = 1;
        ares_freeaddrinfo(result);
}
int main(void)
{
        ares_channel_t *channel;
        struct ares_addrinfo_hints hints = { 0 };
        if (strcmp(ares_version(NULL), "1.34.8") || !ares_threadsafety())
                return 1;
        if (ares_library_init(ARES_LIB_INIT_ALL) || ares_init(&channel))
                return 2;
        /* Numeric address resolution exercises the callback without external DNS. */
        ares_getaddrinfo(channel, "127.0.0.1", "80", &hints, resolved, NULL);
        ares_destroy(channel);
        ares_library_cleanup();
        if (!called)
                return 3;
        puts("c-ares version, thread safety and address callback: OK");
        return 0;
}
