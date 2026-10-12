#include <pcre2posix.h>

int main(void)
{
        regex_t regex;
        if (regcomp(&regex, "devkit", REG_EXTENDED) != 0)
                return 1;
        int result = regexec(&regex, "devkit", 0, NULL, 0);
        regfree(&regex);
        return result != 0;
}
