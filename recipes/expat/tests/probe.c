#include <stdio.h>
#include <string.h>

#include <expat.h>

static void XMLCALL start(void *userData, const XML_Char *name,
                          const XML_Char **atts)
{
        (void)userData;
        (void)atts;
        puts(name);
}

int main(void)
{
        XML_Parser parser = XML_ParserCreate(NULL);
        if (parser == NULL) {
                return 1;
        }
        XML_SetElementHandler(parser, start, NULL);
        const char *document = "<devkit/>";
        if (XML_Parse(parser, document, (int)strlen(document), 1) ==
            XML_STATUS_ERROR) {
                XML_ParserFree(parser);
                return 1;
        }
        XML_ParserFree(parser);
        return 0;
}
