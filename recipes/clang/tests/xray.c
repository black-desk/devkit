#include <xray/xray_interface.h>
__attribute__((noinline, xray_always_instrument)) int answer(void)
{
        return 42;
}
int main(void)
{
        if (__xray_max_function_id() == 0)
                return 2;
        if (__xray_patch() != SUCCESS)
                return 1;
        return answer() == 42 ? 0 : 1;
}
