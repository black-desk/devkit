#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
for feature in pcre2-8 pcre2-16 pcre2-32 unicode jit; do
  test "$(pcre2test -C "$feature")" = 1
done
pcre2test -C | grep -F 'pcre2test has libedit support'
printf '\037\213\010\000\000\000\000\000\002\377\113\316\317\055\050\112\055\056\116\115\121\310\113\115\115\311\111\345\002\000\317\332\054\325\022\000\000\000' > input.gz
test "$(pcre2grep needle input.gz)" = 'compressed needle'
printf '\102\132\150\071\061\101\131\046\123\131\003\002\347\074\000\000\001\121\200\000\020\100\000\016\007\330\000\040\000\061\003\100\320\051\264\006\232\104\001\351\103\025\156\035\104\360\273\222\051\302\204\200\030\027\071\340' > input.bz2
test "$(pcre2grep needle input.bz2)" = 'compressed needle'
pcre2grep --version
pcre2test --version
