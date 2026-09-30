# Share

One-off secret sharing for RahaCloud, served from GitHub Pages at <https://rahacloud.com/share/>.

Secrets are encrypted with [age](https://age-encryption.org), committed to `s/<id>.age`, and decrypted in the browser with a vendored copy of [typage](https://github.com/FiloSottile/typage). Everything after `#` in a link stays in the browser, so GitHub only ever stores and serves ciphertext. There are two kinds of links:

- **One-off** (`just new`): encrypted to a fresh key that travels in the link, `https://rahacloud.com/share/#<id>.<AGE-SECRET-KEY-…>`. Anyone holding the link can read it, so use it for people who have no key.
- **By name** (`just send`): encrypted to the keys of named people and teams, `https://rahacloud.com/share/#<id>`. Only those people's browsers can read it, so the link is safe to post in a group chat.

## Recipients

Each person opens <https://rahacloud.com/share/#setup> once per browser or device. It creates a key that stays in that browser (a non-extractable WebCrypto key in IndexedDB) and shows its public `age1…` key, which they send to us.

The recipient list lives in the private [`rahacloud/secrets`](https://github.com/rahacloud/secrets) repo under `recipients/`, so names never appear here: `people/<name>.pub` holds one or more public keys per person, and `teams/<team>.txt` lists names, one per line. The recipes look for it at `../secrets/recipients`; set `SHARE_RECIPIENTS` to use another path.

## Usage

Requires `age`, `just`, and push access to this repository.

```bash
just new                          # paste the secret, Ctrl-D, get a one-off link
just new ~/kubeconfig.yaml        # share a file's contents
pbpaste | just new                # share the clipboard
just send team:bitbarg,ali        # only the bitbarg team and ali can read it
just send team:talano .env        # a file, for a team

just add-key ali age1…            # register a key someone sent from #setup
just join bitbarg ali             # add a person to a team
just recipients                   # teams, members, and key counts

just list                         # shares and the date each was added
just revoke <id>                  # delete a share before it expires
```

To take someone off a secret, revoke the share and send it again to the remaining people, then rotate the secret, since they may already have read it.

The link works about a minute after `just new`, once the Pages deploy finishes. A daily workflow deletes shares older than 7 days.

## Security model

- The repository and its Pages site are public, so anyone can download every ciphertext. That is safe only because every share is encrypted to random X25519 keys; never switch to passphrase encryption (`age -p`) here, since it would allow offline guessing. age does not record who a file is encrypted to.
- A browser's key cannot be read by scripts, but any script on this origin can use it to decrypt. The strict CSP and review of pushes to `main` are what keep other scripts out.
- Revoking or expiring deletes the file from the site, not from git history. If a link leaks, rotate the secret itself.
- Anyone who can push to `main` can change the page to exfiltrate keys. Keep branch protection on and review changes to `index.html`, `app.js`, and `vendor/`.
- The page loads no third-party code and enforces a strict CSP. Rebuild the vendored library with `just vendor <version>`.
