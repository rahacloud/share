# Share

One-off secret sharing for RahaCloud, served from GitHub Pages at <https://rahacloud.com/share/>.

Each secret is encrypted with [age](https://age-encryption.org) to a fresh X25519 key, committed to `s/<id>.age`, and shared as a link of the form `https://rahacloud.com/share/#<id>.<AGE-SECRET-KEY-…>`. The key lives in the URL fragment, which browsers never send to a server, so GitHub only ever stores and serves ciphertext. The page fetches the file and decrypts it in the browser with a vendored copy of [typage](https://github.com/FiloSottile/typage).

## Usage

Requires `age`, `just`, and push access to this repository.

```bash
just new                    # paste the secret, Ctrl-D, get a link
just new ~/kubeconfig.yaml  # share a file's contents
pbpaste | just new          # share the clipboard
just list                   # shares and the date each was added
just revoke <id>            # delete a share before it expires
```

The link works about a minute after `just new`, once the Pages deploy finishes. A daily workflow deletes shares older than 7 days.

## Security model

- The repository and its Pages site are public, so anyone can download every ciphertext. That is safe only because every share has its own random 256-bit key; never switch to passphrase encryption (`age -p`) here, since it would allow offline guessing.
- Revoking or expiring deletes the file from the site, not from git history. If a link leaks, rotate the secret itself.
- Anyone who can push to `main` can change the page to exfiltrate keys. Keep branch protection on and review changes to `index.html`, `app.js`, and `vendor/`.
- The page loads no third-party code and enforces a strict CSP. Rebuild the vendored library with `just vendor <version>`.
