"""Thuat toan ma kich hoat SDOpLat - phai khop tung buoc voi license_module.lsp."""
ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

def lic_hash(s):
    h = [5381, 52711, 40503, 12289]; m = [31, 33, 37, 41]; n = len(s)
    for _ in range(2):
        for i in range(1, n + 1):
            c = ord(s[i - 1])
            for k in range(4):
                pv = (h[(k + 3) % 4] >> 5) & 255
                h[k] = ((h[k] * m[k] + c + pv + (i % 251)) ^ (h[k] >> 9)) & 16777215
    return h

def lic_chars(h, counts):
    return ''.join(ABC[(h[i] >> (5 * j)) & 31] for i, cnt in enumerate(counts) for j in range(cnt))

def lic_code(s):
    r = lic_chars(lic_hash(s), (4, 4, 4, 3))
    return f"{r[0:5]}-{r[5:10]}-{r[10:15]}"

def lic_mid_of(raw):
    r = lic_chars(lic_hash(raw), (3, 3, 3, 3))
    return f"{r[0:4]}-{r[4:8]}-{r[8:12]}"

def activation_code(machine_id, secret):
    return lic_code(f"{machine_id}|{secret}")

def norm(s):
    return ''.join(ch for ch in s.upper() if ch.isalnum() and ch.isascii())
