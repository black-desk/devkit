#define _GNU_SOURCE
#include <dlfcn.h>

#include <algorithm>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <execinfo.h>
#include <link.h>

struct Libraries {
        const char *prefix;
        int seen = 0;
        bool valid = true;
};

static int check_library(dl_phdr_info *info, size_t, void *argument)
{
        auto &libraries = *static_cast<Libraries *>(argument);
        std::string path(info->dlpi_name);
        if (path.find("libstdc++") != std::string::npos) {
                libraries.valid = false;
        }
        if (path.find("libc++.so") != std::string::npos ||
            path.find("libc++abi.so") != std::string::npos ||
            path.find("libunwind.so") != std::string::npos ||
            path.find("libgcc_s.so") != std::string::npos) {
                ++libraries.seen;
                libraries.valid &= path.starts_with(libraries.prefix);
        }
        return 0;
}

int main(int argc, char **argv)
{
        if (argc != 2) {
                return 1;
        }
        std::vector<int> numbers{ 3, 1, 2 };
        std::sort(numbers.begin(), numbers.end());
        std::thread worker([&] { numbers.push_back(4); });
        worker.join();
        try {
                throw std::runtime_error("libc++ exception probe");
        } catch (const std::runtime_error &error) {
                if (std::string(error.what()) != "libc++ exception probe") {
                        return 1;
                }
        }
        if (numbers != std::vector<int>{ 1, 2, 3, 4 } ||
            !std::filesystem::exists(std::filesystem::current_path())) {
                return 1;
        }
        // Exercise glibc's indirect libgcc load after C++ has loaded its unwinder.
        void *addresses[32];
        if (backtrace(addresses, 32) == 0) {
                return 1;
        }
        Libraries libraries{ argv[1] };
        dl_iterate_phdr(check_library, &libraries);
        if (!libraries.valid || libraries.seen != 3) {
                return 1;
        }
        std::cout << "channel libc++, ABI, and LLVM unwinder: OK\n";
}
