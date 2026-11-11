/* Read-only differential probe using the separately installed NUT C library.
 * Original test adapter; no upstream implementation is embedded here. */
#include <stdint.h>
#include <sys/types.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <upsclient.h>

int main(int argc, char **argv)
{
    UPSCONN_t connection;
    char reply[4096];
    int result = 1;
    if (argc != 4) return 2;
    if (strcmp(argv[3], "NUMLOGINS") && strcmp(argv[3], "NETVER") &&
        strcmp(argv[3], "PROTVER") && strcmp(argv[3], "VER") &&
        strcmp(argv[3], "HELP")) return 2;
    if (upscli_connect(&connection, argv[1], (unsigned short)atoi(argv[2]), UPSCLI_CONN_TRYSSL) < 0) return 1;
    if (!strcmp(argv[3], "NUMLOGINS")) {
        const char *query[] = {"NUMLOGINS", "demo"};
        size_t count = 0;
        char **answer = NULL;
        if (!upscli_get(&connection, 2, query, &count, &answer) && count == 3) {
            puts(answer[2]);
            result = 0;
        }
    } else {
        char command[32];
        int length = snprintf(command, sizeof(command), "%s\n", argv[3]);
        if (!upscli_sendline(&connection, command, (size_t)length) &&
            !upscli_readline(&connection, reply, sizeof(reply))) {
            puts(reply);
            result = 0;
        }
    }
    upscli_disconnect(&connection);
    return result;
}
