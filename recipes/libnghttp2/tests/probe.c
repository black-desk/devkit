#include <stdio.h>
#include <string.h>

#include <nghttp2/nghttp2.h>

int main(void)
{
        nghttp2_session_callbacks *callbacks;
        nghttp2_session *session;
        const unsigned char *data;
        nghttp2_settings_entry setting = {
                NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 100
        };
        if (strcmp(nghttp2_version(0)->version_str, "1.68.1"))
                return 1;
        if (nghttp2_session_callbacks_new(&callbacks))
                return 2;
        if (nghttp2_session_client_new(&session, callbacks, NULL))
                return 3;
        if (nghttp2_submit_settings(session, NGHTTP2_FLAG_NONE, &setting, 1))
                return 4;
        if (nghttp2_session_mem_send(session, &data) !=
                    NGHTTP2_CLIENT_MAGIC_LEN ||
            memcmp(data, NGHTTP2_CLIENT_MAGIC, NGHTTP2_CLIENT_MAGIC_LEN))
                return 5;
        if (nghttp2_session_mem_send(session, &data) <= 0)
                return 6;
        nghttp2_session_del(session);
        nghttp2_session_callbacks_del(callbacks);
        puts("HTTP/2 client preface and SETTINGS serialization: OK");
        return 0;
}
