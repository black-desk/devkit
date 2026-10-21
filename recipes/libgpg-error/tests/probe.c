#include <gpg-error.h>
int main(void)
{
        return !gpg_error_check_version(0);
}
