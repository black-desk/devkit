#include <stdio.h>

#include <ev.h>
#include <event.h>
static int fired;
static void timer(EV_P_ ev_timer *watcher, int events)
{
        (void)events;
        ++fired;
        ev_timer_stop(EV_A_ watcher);
}
int main(void)
{
        struct ev_loop *loop = ev_loop_new(0);
        ev_timer watcher;
        if (!loop || ev_version_major() != 4 || ev_version_minor() != 33)
                return 1;
        ev_timer_init(&watcher, timer, 0.001, 0);
        ev_timer_start(loop, &watcher);
        ev_run(loop, 0);
        ev_loop_destroy(loop);
        if (fired != 1 || !event_get_version())
                return 2;
        puts("libev timer and libevent compatibility interface: OK");
        return 0;
}
