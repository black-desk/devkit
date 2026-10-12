#include <dap/session.h>
int main()
{
        return dap::Session::create() ? 0 : 1;
}
