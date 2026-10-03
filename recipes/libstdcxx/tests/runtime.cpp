#include <dlfcn.h>

#include <iostream>

int main()
{
        Dl_info info{};
        if (!dladdr(dlsym(RTLD_DEFAULT, "__cxa_throw"), &info)) {
                return 1;
        }
        std::cout << info.dli_fname << '\n';
        return 0;
}
