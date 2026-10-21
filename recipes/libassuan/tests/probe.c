#include <assuan.h>
int main(void)
{
        assuan_context_t ctx;
        if (assuan_new(&ctx))
                return 1;
        assuan_release(ctx);
        return 0;
}
