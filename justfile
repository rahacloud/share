base_url := "https://rahacloud.com/share/"

default:
    @just --list

# Encrypt a secret from a file (or stdin), push it, and print the link
new file="-":
    #!/usr/bin/env bash
    set -euo pipefail
    id="$(openssl rand -hex 16)"
    key="$(age-keygen 2>/dev/null | grep '^AGE-SECRET-KEY-')"
    recipient="$(age-keygen -y <<<"$key")"
    if [[ "{{ file }}" == "-" && -t 0 ]]; then
        echo "Paste the secret, then press Ctrl-D:" >&2
    fi
    age -r "$recipient" -o "s/$id.age" "{{ file }}"
    git add "s/$id.age"
    git commit --quiet -m "share: add $id"
    git push --quiet
    echo "{{ base_url }}#$id.$key"
    echo "Live in about a minute, once the Pages deploy finishes." >&2

# Delete a shared secret before it expires
revoke id:
    @git rm --quiet "s/{{ id }}.age"
    @git commit --quiet -m "share: revoke {{ id }}"
    @git push --quiet

# List shared secrets with the date each one was added
list:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in s/*.age; do
        [[ -e "$f" ]] || continue
        printf '%s  %s\n' "$(git log -1 --format=%cs -- "$f")" "$(basename "$f" .age)"
    done

# Delete shares older than the given number of days (run daily by CI)
expire days="7":
    #!/usr/bin/env bash
    set -euo pipefail
    cutoff="$(( $(date +%s) - {{ days }} * 86400 ))"
    for f in s/*.age; do
        [[ -e "$f" ]] || continue
        if (( $(git log -1 --format=%ct -- "$f") < cutoff )); then
            git rm --quiet "$f"
            echo "expired $(basename "$f" .age)"
        fi
    done

# Serve the page locally on http://localhost:8000
serve:
    python3 -m http.server 8000

# Rebuild the vendored age decrypter from npm
vendor version="0.3.1":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    cd "$tmp"
    npm init -y >/dev/null
    npm install --silent "age-encryption@{{ version }}" esbuild
    echo 'export { Decrypter } from "age-encryption";' > entry.js
    npx esbuild entry.js --bundle --format=esm --minify --outfile="{{ justfile_directory() }}/vendor/age-{{ version }}.js"
