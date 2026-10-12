#include <stdio.h>
#include <string.h>

#include <uv.h>
static int fired;
static void timer(uv_timer_t *handle)
{
        ++fired;
        uv_close((uv_handle_t *)handle, NULL);
}
int main(int argc, char **argv)
{
        uv_loop_t loop;
        uv_timer_t handle;
        if (argc != 2 || strcmp(uv_version_string(), argv[1]))
                return 1;
        if (uv_loop_init(&loop) || uv_timer_init(&loop, &handle))
                return 2;
        if (uv_timer_start(&handle, timer, 1, 0))
                return 3;
        uv_run(&loop, UV_RUN_DEFAULT);
        if (fired != 1 || uv_loop_close(&loop))
                return 4;
        printf("libuv event-loop timer: OK (%s)\n", uv_version_string());
}
