#include <string.h>

#include <talloc.h>
static int destroyed = 0;
static int destroy(char *ptr)
{
        destroyed++;
        return 0;
}
int main(void)
{
        void *root = talloc_new(NULL);
        char *child = talloc_strdup(root, "devkit");
        if (!root || !child || strcmp(child, "devkit") ||
            talloc_total_blocks(root) != 2)
                return 1;
        talloc_set_destructor(child, destroy);
        talloc_free(root);
        return destroyed != 1;
}
