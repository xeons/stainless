/*
 * Console output. Writes a String's bytes exactly as they are: the text is
 * already UTF-8, so nothing is transcoded on the way out.
 */

#include "stainless.h"

#include <stdio.h>

void sl_console_write(void *pointer)
{
    SlString *string = (SlString *)pointer;
    fwrite(sl_string_data(string), 1, string->byteLength, stdout);
}

void sl_console_write_line(void *pointer)
{
    sl_console_write(pointer);
    fputc(0x0A, stdout);
}

void sl_console_write_error(void *pointer)
{
    SlString *string = (SlString *)pointer;
    fwrite(sl_string_data(string), 1, string->byteLength, stderr);
    fputc(0x0A, stderr);
}
