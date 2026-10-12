#include <dlfcn.h>
#include <pthread.h>

#include <atomic>
#include <charconv>
#include <exception>
#include <future>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

#include <link.h>

static std::atomic<bool> ready{ false };
static std::atomic<int> destroyed{ 0 };
struct Guard {
        ~Guard()
        {
                ++destroyed;
        }
};
static void *worker(void *)
{
        Guard guard;
        ready = true;
        for (;;) {
                pthread_testcancel();
                std::this_thread::yield();
        }
}
struct Libraries {
        std::string prefix;
        int gcc = 0;
        int cpp = 0;
        bool outside = false;
};
static int library(struct dl_phdr_info *info, size_t, void *data)
{
        auto &libs = *static_cast<Libraries *>(data);
        const std::string path = info->dlpi_name;
        if (path.find("libgcc_s.so.1") != std::string::npos) {
                ++libs.gcc;
                libs.outside |= path.find(libs.prefix + "/") != 0;
                std::cout << "unwinder: " << path << '\n';
        }
        if (path.find("libstdc++.so.6") != std::string::npos) {
                ++libs.cpp;
                libs.outside |= path.find(libs.prefix + "/") != 0;
                std::cout << "GNU standard library: " << path << '\n';
        }
        return 0;
}
int main(int argc, char **argv)
{
        if (argc != 3)
                return 1;
        int caught = 0;
        for (int i = 0; i < 1000; ++i) {
                try {
                        Guard guard;
                        throw std::runtime_error("exception");
                } catch (const std::runtime_error &) {
                        ++caught;
                }
        }
        if (caught != 1000 || destroyed != 1000)
                return 2;
        try {
                try {
                        throw std::logic_error("inner");
                } catch (...) {
                        std::throw_with_nested(std::runtime_error("outer"));
                }
        } catch (const std::exception &outer) {
                try {
                        std::rethrow_if_nested(outer);
                } catch (const std::logic_error &inner) {
                        if (std::string(inner.what()) != "inner")
                                return 3;
                        ++caught;
                }
        }
        if (caught != 1001)
                return 4;
        auto future = std::async(std::launch::async, []() -> int {
                Guard guard;
                throw std::runtime_error("future");
        });
        try {
                future.get();
                return 5;
        } catch (const std::runtime_error &e) {
                if (std::string(e.what()) != "future")
                        return 6;
        }
        void *plugin = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
        if (!plugin) {
                std::cerr << dlerror() << '\n';
                return 7;
        }
        auto throwing = reinterpret_cast<void (*)()>(
                dlsym(plugin, "throw_from_plugin"));
        if (!throwing)
                return 8;
        try {
                throwing();
                return 9;
        } catch (const std::runtime_error &e) {
                if (std::string(e.what()) != "plugin")
                        return 10;
        }
        dlclose(plugin);
        pthread_t thread;
        if (pthread_create(&thread, nullptr, worker, nullptr))
                return 11;
        while (!ready)
                std::this_thread::yield();
        if (pthread_cancel(thread))
                return 12;
        void *result = nullptr;
        if (pthread_join(thread, &result) || result != PTHREAD_CANCELED ||
            destroyed != 1002)
                return 13;
        long double number = 0;
        const char value[] = "125.75";
        auto conversion = std::from_chars(value, value + 6, number);
        if (conversion.ec != std::errc() || number != 125.75L)
                return 14;
        std::ostringstream formatted;
        formatted << number;
        if (formatted.str() != "125.75")
                return 15;
        Libraries libs{ argv[1] };
        dl_iterate_phdr(library, &libs);
        if (libs.gcc != 1 || libs.cpp != 1 || libs.outside)
                return 16;
        std::cout
                << "exceptions, nested/thread/DSO propagation, cancellation and long double: OK\n";
}
