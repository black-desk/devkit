#include <gpgme.h>
int main(void)
{
        return !gpgme_check_version(0);
}
