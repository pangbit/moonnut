"""Explicitly bounded normalization for official NSS CLI comparisons."""
NSS_DIAGNOSTICS = {
    'Init SSL without certificate database',
    "Connecting in SSL to '127.0.0.1' (no certificate name specified)",
    'Do not intend to authenticate server 127.0.0.1',
    'SSL handshake done successfully with server 127.0.0.1',
    'Connected to NUT server 127.0.0.1 in SSL',
    'Certificate verification is disabled',
}


def semantic_stderr(text):
    # Preserve every other byte, including prompts, whitespace and error text.
    return ''.join(line for line in text.splitlines(keepends=True)
                   if line.rstrip('\n') not in NSS_DIAGNOSTICS)

