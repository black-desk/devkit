#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#include <execinfo.h>
#include <link.h>
#include <unwind.h>

static _Unwind_Reason_Code count_frame(struct _Unwind_Context *context,
                                       void *argument)
{
        (void)context;
        ++*(int *)argument;
        return _URC_NO_REASON;
}

static int count_unwinders(struct dl_phdr_info *info, size_t size,
                           void *argument)
{
        (void)size;
        if (strstr(info->dlpi_name, "/libgcc_s.so") ||
            strstr(info->dlpi_name, "/libunwind.so")) {
                ++*(int *)argument;
        }
        return 0;
}

int main(int argc, char **argv)
{
        if (argc != 2) {
                return 1;
        }
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        if (!library) {
                fprintf(stderr, "%s\n", dlerror());
                return 1;
        }
        /* Both an absolute-path load and the libunwind alias must register the
     libgcc SONAME before glibc requests it. Do not mask this with loader env. */
        void *registered = dlopen("libgcc_s.so.1", RTLD_NOW | RTLD_NOLOAD);
        if (!registered || dlsym(registered, "_Unwind_Backtrace") !=
                                   dlsym(library, "_Unwind_Backtrace")) {
                fprintf(stderr,
                        "libgcc identity was not registered for this unwinder\n");
                return 1;
        }
        typedef _Unwind_Reason_Code (*backtrace_fn)(_Unwind_Trace_Fn, void *);
        backtrace_fn trace =
                (backtrace_fn)dlvsym(library, "_Unwind_Backtrace", "GCC_3.3");
        if (!trace || !dlvsym(library, "_Unwind_RaiseException", "GCC_3.0") ||
            !dlvsym(library, "_Unwind_GetIPInfo", "GCC_4.2.0")) {
                fprintf(stderr, "missing versioned unwind interface\n");
                return 1;
        }
        typedef __int128 (*division_fn)(__int128, __int128);
        division_fn divide =
                (division_fn)dlvsym(library, "__divti3", "GCC_3.0");
        if (!divide || divide(40, 5) != 8) {
                return 1;
        }
        int frames = 0;
        trace(count_frame, &frames);
        void *addresses[32];
        if (frames == 0 || backtrace(addresses, 32) == 0) {
                return 1;
        }
        int unwinders = 0;
        dl_iterate_phdr(count_unwinders, &unwinders);
        if (unwinders != 1) {
                fprintf(stderr, "expected one unwinder, loaded %d\n",
                        unwinders);
                return 1;
        }
        puts("versioned LLVM libgcc interfaces and glibc backtrace: OK");
        return 0;
}
