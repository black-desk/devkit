#include <stdlib.h>
int main(int argc, char **argv)
{
        (void)argv;
        volatile int index = argc + 16;
        volatile char *p = malloc(8);
        p[index] = 1;
        free((void *)p);
        return 0;
}
