#include <gio/gio.h>
int main(void)
{
        GFile *f = g_file_new_for_path(".");
        char *p = g_file_get_path(f);
        int ok = g_path_is_absolute(p);
        g_free(p);
        g_object_unref(f);
        return !ok;
}
