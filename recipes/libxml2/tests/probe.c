#include <libxml/parser.h>

int main(void)
{
        const char document[] = "<root>devkit</root>";
        xmlDocPtr parsed =
                xmlReadMemory(document, sizeof(document) - 1, NULL, NULL, 0);
        if (!parsed)
                return 1;
        xmlFreeDoc(parsed);
        xmlCleanupParser();
        return 0;
}
