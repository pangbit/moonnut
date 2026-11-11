/* POSIX CLI prompt support only; no device, subprocess or shutdown access. */
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE 1
#endif
#include <moonbit.h>
#include <stdio.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#include <pwd.h>
#endif

static moonbit_bytes_t copy_text(const char *text)
{
    size_t n = text ? strlen(text) : 0;
    moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)n);
    if (n) memcpy(bytes, text, n);
    return bytes;
}
MOONBIT_FFI_EXPORT moonbit_bytes_t moonnut_cli_default_user(void)
{
#ifndef _WIN32
    struct passwd *entry = getpwuid(getuid());
    return copy_text(entry ? entry->pw_name : NULL);
#else
    return copy_text(NULL);
#endif
}
MOONBIT_FFI_EXPORT moonbit_bytes_t moonnut_cli_read_line(void)
{
    char line[512];
    return copy_text(fgets(line, sizeof(line), stdin) ? line : NULL);
}
MOONBIT_FFI_EXPORT moonbit_bytes_t moonnut_cli_password(void)
{
#ifndef _WIN32
    char *password = getpass("Password: ");
    size_t n = password ? strlen(password) : 0;
    moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)n + 1);
    result[0] = password ? 1 : 0;
    if (n) memcpy(result + 1, password, n);
    return result;
#else
    return moonbit_make_bytes(1, 0);
#endif
}
