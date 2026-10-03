#include <gio/gio.h>
#include <glib-object.h>
int main(void)
{
        GError *error = NULL;
        GRegex *regex = g_regex_new("^devkit[0-9]+$", 0, 0, &error);
        if (!regex || !g_regex_match(regex, "devkit42", 0, NULL))
                return 1;
        g_regex_unref(regex);
        GObject *obj = g_object_new(G_TYPE_OBJECT, NULL);
        g_object_unref(obj);
        GOutputStream *out = g_memory_output_stream_new_resizable();
        gsize written;
        if (!g_output_stream_write_all(out, "hello", 5, &written, NULL, &error))
                return 1;
        if (written != 5 || g_memory_output_stream_get_data_size(
                                    G_MEMORY_OUTPUT_STREAM(out)) != 5)
                return 1;
        g_object_unref(out);
        return 0;
}
