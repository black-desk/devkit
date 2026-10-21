#include <string.h>

#include <gmime/gmime.h>
int main(void)
{
        g_mime_init();
        GMimeMessage *m = g_mime_message_new(0);
        g_mime_message_set_subject(m, "devkit", "utf-8");
        int ok = !strcmp(g_mime_message_get_subject(m), "devkit");
        g_object_unref(m);
        g_mime_shutdown();
        return !ok;
}
