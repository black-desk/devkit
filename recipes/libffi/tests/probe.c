#include <ffi.h>
int main(void)
{
        ffi_cif cif;
        return ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 0, &ffi_type_void, 0) !=
               FFI_OK;
}
