#include <stdio.h>
#include <string.h>

#include <histedit.h>
int main(void)
{
        History *h = history_init();
        HistEvent event;
        Tokenizer *t = tok_init(NULL);
        const char **argv;
        int argc;
        if (!h || !t)
                return 1;
        if (history(h, &event, H_SETSIZE, 8) < 0 ||
            history(h, &event, H_ENTER, "bootstrap command") < 0 ||
            history(h, &event, H_FIRST) < 0 ||
            strcmp(event.str, "bootstrap command"))
                return 2;
        if (tok_str(t, "one 'two three'", &argc, &argv) != 0 || argc != 2 ||
            strcmp(argv[1], "two three"))
                return 3;
        tok_end(t);
        history_end(h);
        puts("libedit history and quoted tokenization: OK");
        return 0;
}
