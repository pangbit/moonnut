/* Original session differential adapter for a disposable loopback upsd.
 * Uses the installed official libupsclient. No UPS writes, commands or FSD. */
#include <stdint.h>
#include <sys/types.h>
#include <sys/time.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <upsclient.h>

static char reply[4096];
static void die(void) { fputs("NUT session fixture failed\n", stderr); exit(1); }

static void request(UPSCONN_t *c, const char *command, int print)
{
    size_t length = strlen(command);
    if (upscli_sendline(c, command, length) || upscli_readline(c, reply, sizeof(reply))) die();
    if (print) puts(reply);
}

static void credential(UPSCONN_t *c, const char *kind, const char *value)
{
    char command[256];
    int n = snprintf(command, sizeof(command), "%s \"%s\"\n", kind, value);
    if (n < 0 || (size_t)n >= sizeof(command)) die();
    request(c, command, 1);
}

static void clients(UPSCONN_t *c)
{
    const char *query[] = {"CLIENT", "demo"};
    size_t count = 0;
    char **answer = NULL;
    int more;
    if (upscli_list_start(c, 2, query)) die();
    fputs("CLIENTS", stdout);
    while ((more = upscli_list_next(c, 2, query, &count, &answer)) == 1) {
        if (count != 3) die();
        printf(" %s", answer[2]);
    }
    if (more < 0) die();
    putchar('\n');
}

static void count(UPSCONN_t *c, int wanted)
{
    int value = -1;
    struct timespec pause = {0, 20000000};
    for (int attempt = 0; attempt < 51; ++attempt) {
        request(c, "GET NUMLOGINS demo\n", 0);
        if (sscanf(reply, "NUMLOGINS demo %d", &value) != 1) die();
        if (wanted < 0 || value == wanted) break;
        nanosleep(&pause, NULL);
    }
    if (wanted >= 0 && value != wanted) die();
    puts(reply);
}

static void value(UPSCONN_t *c)
{
    const char *query[] = {"VAR", "demo", "ups.status"};
    size_t count = 0;
    char **answer = NULL;
    if (upscli_get(c, 3, query, &count, &answer) || count != 4) die();
    printf("VALUE %s\n", answer[3]);
}

static void connect_to(UPSCONN_t *c, unsigned short port, int flags)
{
    if (upscli_connect(c, "127.0.0.1", port, flags)) die();
}

int main(int argc, char **argv)
{
    UPSCONN_t first, second, fresh;
    const char *user = getenv("MOONNUT_USERNAME"), *password = getenv("MOONNUT_PASSWORD");
    int flags = getenv("MOONNUT_SESSION_PLAINTEXT") ? 0 : UPSCLI_CONN_TRYSSL;
    if (argc != 2 || !user || !password) return 2;
    unsigned short port = (unsigned short)atoi(argv[1]);
    signal(SIGPIPE, SIG_IGN);
    connect_to(&first, port, flags);
    request(&first, "GET TRACKING\n", 1);
    request(&first, "GET TRACKING fixture-unknown\n", 1);
    request(&first, "SET TRACKING ON\n", 1);
    request(&first, "LOGIN demo\n", 1);
    credential(&first, "USERNAME", user);
    credential(&first, "USERNAME", user);
    request(&first, "SET TRACKING ON\n", 1);
    request(&first, "LOGIN demo\n", 1);
    credential(&first, "PASSWORD", password);
    credential(&first, "PASSWORD", password);
    count(&first, -1);
    clients(&first);
    request(&first, "SET TRACKING ON\n", 1);
    request(&first, "SET TRACKING ON\n", 1);
    request(&first, "GET TRACKING\n", 1);
    request(&first, "GET TRACKING fixture-unknown\n", 1);
    request(&first, "SET TRACKING OFF\n", 1);
    request(&first, "GET TRACKING\n", 1);
    request(&first, "GET TRACKING fixture-unknown\n", 1);
    request(&first, "SET TRACKING ON\n", 1);
    request(&first, "LOGIN missing\n", 1);
    request(&first, "LOGIN demo\n", 1);
    request(&first, "LOGIN demo\n", 1);
    count(&first, -1);
    clients(&first);
    value(&first);
    connect_to(&second, port, flags);
    request(&second, "GET TRACKING\n", 1);
    credential(&second, "USERNAME", user);
    credential(&second, "PASSWORD", password);
    request(&second, "LOGIN demo\n", 1);
    count(&first, -1);
    clients(&first);
    request(&second, "LOGOUT\n", 1);
    upscli_disconnect(&second);
    count(&first, 1);
    request(&first, "LOGOUT\n", 1);
    upscli_disconnect(&first);
    connect_to(&fresh, port, flags);
    request(&fresh, "GET TRACKING\n", 1);
    count(&fresh, 0);
    credential(&fresh, "PASSWORD", "wrong-fixture-password");
    credential(&fresh, "USERNAME", user);
    request(&fresh, "SET TRACKING ON\n", 1);
    request(&fresh, "GET TRACKING\n", 1);
    request(&fresh, "LOGIN demo\n", 1);
    value(&fresh);
    request(&fresh, "LOGOUT\n", 1);
    upscli_disconnect(&fresh);
    return 0;
}
