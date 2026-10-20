#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Devkit::PrefixProbe    PACKAGE = Devkit::PrefixProbe

PROTOTYPES: DISABLE

int
answer()
    CODE:
        RETVAL = 42;
    OUTPUT:
        RETVAL
