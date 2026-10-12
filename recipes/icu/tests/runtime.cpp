#include <cstdio>

#include <unicode/icudataver.h>
#include <unicode/ucnv.h>
#include <unicode/ucol.h>
#include <unicode/udat.h>
#include <unicode/uloc.h>
int main()
{
        UErrorCode status = U_ZERO_ERROR;
        UVersionInfo version;
        u_getDataVersion(version, &status);
        if (U_FAILURE(status))
                return 1;
        UConverter *converter = ucnv_open("GB18030", &status);
        if (U_FAILURE(status) || !converter)
                return 2;
        ucnv_close(converter);
        UCollator *collator = ucol_open("zh_CN", &status);
        if (U_FAILURE(status) || !collator)
                return 3;
        ucol_close(collator);
        UDateFormat *format = udat_open(UDAT_FULL, UDAT_FULL, "ar_EG", nullptr,
                                        0, nullptr, 0, &status);
        if (U_FAILURE(status) || !format)
                return 4;
        udat_close(format);
        int locales = uloc_countAvailable(), converters = ucnv_countAvailable();
        if (locales < 500 || converters < 100)
                return 5;
        std::printf(
                "data=%u.%u locales=%d converters=%d; GB18030, zh_CN collation, ar_EG dates: OK\n",
                version[0], version[1], locales, converters);
}
