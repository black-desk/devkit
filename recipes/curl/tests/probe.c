#include <stdio.h>
#include <string.h>

#include <curl/curl.h>

int main(void)
{
        const curl_version_info_data *version =
                curl_version_info(CURLVERSION_NOW);
        const unsigned required = CURL_VERSION_SSL | CURL_VERSION_LIBZ |
                                  CURL_VERSION_HTTP2 | CURL_VERSION_GSSAPI |
                                  CURL_VERSION_SPNEGO | CURL_VERSION_PSL |
                                  CURL_VERSION_ZSTD;
        const char *const *protocol;
        int sftp = 0, scp = 0;
        CURL *handle;
        if (strcmp(version->version, "8.22.0") ||
            (version->features & required) != required)
                return 1;
        for (protocol = version->protocols; *protocol; ++protocol) {
                sftp |= !strcmp(*protocol, "sftp");
                scp |= !strcmp(*protocol, "scp");
        }
        if (!sftp || !scp || curl_global_init(CURL_GLOBAL_DEFAULT))
                return 2;
        handle = curl_easy_init();
        if (!handle)
                return 3;
        if (curl_easy_setopt(handle, CURLOPT_HTTP_VERSION,
                             CURL_HTTP_VERSION_2TLS))
                return 4;
        curl_easy_cleanup(handle);
        curl_global_cleanup();
        puts("libcurl HTTP/2, SSH, GSSAPI, PSL and compression support: OK");
        return 0;
}
