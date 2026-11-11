/* Original differential adapter using official libupsclient, fixed loopback
 * endpoint and artificial commands only. Run solely with control_integration.py. */
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
static void die(void) { fputs("NUT control fixture failed\n", stderr); exit(1); }
static void pause_poll(void) { struct timespec t = {0, 20000000}; nanosleep(&t, NULL); }
static void request(UPSCONN_t *c, const char *label, const char *command)
{
    if (upscli_sendline(c, command, strlen(command)) || upscli_readline(c, reply, sizeof(reply))) die();
    if (label) printf("%s %s\n", label, reply);
}
static void authenticate(UPSCONN_t *c, const char *kind, const char *value)
{
    char command[256];
    int n = snprintf(command, sizeof(command), "%s \"%s\"\n", kind, value);
    if (n < 0 || (size_t)n >= sizeof(command)) die();
    request(c, NULL, command);
    if (strcmp(reply, "OK")) die();
}
static void connect_to(UPSCONN_t *c, unsigned short port)
{
    if (upscli_connect(c, "127.0.0.1", port, UPSCLI_CONN_TRYSSL)) die();
}
static void receipt(UPSCONN_t *c, const char *label, const char *command, char *id)
{
    request(c, label, command);
    if (strncmp(reply, "OK TRACKING ", 12) || strlen(reply + 12) != 36) die();
    memcpy(id, reply + 12, 37);
}
static void status(UPSCONN_t *c, const char *label, const char *id, int wait)
{
    char command[128];
    snprintf(command, sizeof(command), "GET TRACKING %s\n", id);
    for (int i = 0; i <= 100; ++i) {
        request(c, NULL, command);
        if (!wait || strcmp(reply, "PENDING")) break;
        pause_poll();
    }
    if (wait && !strcmp(reply, "PENDING")) die();
    printf("%s %s\n", label, reply);
}
static void value(UPSCONN_t *c, const char *label, const char *name, const char *wanted)
{
    const char *query[] = {"VAR", "control", name};
    size_t count = 0;
    char **answer = NULL;
    for (int i = 0; i <= 100; ++i) {
        if (upscli_get(c, 3, query, &count, &answer) || count != 4) die();
        if (!wanted || !strcmp(answer[3], wanted)) break;
        pause_poll();
    }
    if (wanted && strcmp(answer[3], wanted)) die();
    printf("%s %s\n", label, answer[3]);
}
int main(int argc, char **argv)
{
    UPSCONN_t denied, c, fresh;
    char id[37], command[256], label[64];
    const char *password = getenv("MOONNUT_PASSWORD");
    const char *names[] = {"success", "invalid", "failed", "unknown", "conversion"};
    if (argc != 2 || !password) return 2;
    unsigned short port = (unsigned short)atoi(argv[1]);
    signal(SIGPIPE, SIG_IGN);
    connect_to(&denied, port);
    request(&denied, "no-user", "SET VAR control ups.id x\n");
    authenticate(&denied, "USERNAME", "reader");
    request(&denied, "no-password", "SET VAR control ups.id x\n");
    authenticate(&denied, "PASSWORD", password);
    request(&denied, "denied-set", "SET VAR control missing x\n");
    request(&denied, "denied-unknown-cmd", "INSTCMD control missing\n");
    request(&denied, "denied-cmd", "INSTCMD control fixture.success\n");
    request(&denied, "denied-primary", "PRIMARY control\n");
    request(&denied, "denied-master", "MASTER control\n");
    request(&denied, "denied-fsd", "FSD control\n");
    upscli_disconnect(&denied);
    connect_to(&c, port);
    authenticate(&c, "USERNAME", "operator");
    authenticate(&c, "PASSWORD", password);
    request(&c, "primary", "PRIMARY control\n");
    request(&c, "master", "MASTER control\n");
    request(&c, NULL, "GET NUMLOGINS control\n");
    if (strncmp(reply, "NUMLOGINS control ", 18)) die();
    printf("logins %s\n", reply + 18);
    request(&c, "missing-primary", "PRIMARY missing\n");
    request(&c, "missing-master", "MASTER missing\n");
    request(&c, "missing-fsd", "FSD missing\n");
    request(&c, "missing-ups", "SET VAR missing ups.id x\n");
    request(&c, "missing-var", "SET VAR control missing x\n");
    request(&c, "readonly", "SET VAR control ups.status x\n");
    request(&c, "too-long", "SET VAR control ups.id 01234567890123456\n");
    request(&c, "invalid-enum", "SET VAR control ups.beeper.status other\n");
    request(&c, "range-gap", "SET VAR control input.transfer.low 101\n");
    request(&c, "delayed-set", "SET VAR control ups.id \"a\\\"b\\\\c\\#d\"\n");
    value(&c, "before-apply", "ups.id", NULL);
    request(&c, "release-set", "INSTCMD control fixture.release\n");
    value(&c, "after-apply", "ups.id", "a\"b\\c#d");
    request(&c, NULL, "SET TRACKING ON\n");
    receipt(&c, "range-text", "SET VAR control input.transfer.low 102tail\n", id);
    status(&c, "range-result", id, 1);
    value(&c, "range-value", "input.transfer.low", "102tail");
    receipt(&c, "hold", "INSTCMD control fixture.hold\n", id);
    status(&c, "held-result", id, 0);
    request(&c, NULL, "SET TRACKING OFF\n");
    request(&c, "release-held", "INSTCMD control fixture.release\n");
    request(&c, NULL, "SET TRACKING ON\n");
    status(&c, "released-result", id, 1);
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); ++i) {
        snprintf(command, sizeof(command), "INSTCMD control fixture.%s\n", names[i]);
        receipt(&c, names[i], command, id);
        snprintf(label, sizeof(label), "%s-result", names[i]);
        status(&c, label, id, 1);
    }
    request(&c, NULL, "SET TRACKING OFF\n");
    request(&c, "absent", "INSTCMD control fixture.success\n");
    request(&c, "empty", "INSTCMD control fixture.success \"\"\n");
    request(&c, "escaped", "INSTCMD control fixture.success \"a\\\"b\\\\c\\#d\"\n");
    request(&c, "multiword", "INSTCMD control fixture.success \"two words\"\n");
    request(&c, NULL, "SET TRACKING ON\n");
    receipt(&c, "barrier", "INSTCMD control fixture.success\n", id);
    status(&c, "barrier-result", id, 1);
    value(&c, "before-fsd", "ups.status", NULL);
    request(&c, "fsd", "FSD control\n");
    request(&c, "fsd-again", "FSD control\n");
    value(&c, "after-fsd", "ups.status", NULL);
    upscli_disconnect(&c);
    connect_to(&fresh, port);
    value(&fresh, "fresh-fsd", "ups.status", NULL);
    upscli_disconnect(&fresh);
    return 0;
}
