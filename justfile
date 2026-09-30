base_url := "https://rahacloud.com/share/"

# People's public keys and team membership; kept in the private secrets repo so
# names never appear in this public one.
recipients := env("SHARE_RECIPIENTS", justfile_directory() / "../secrets/recipients")

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

# Encrypt a secret for people and teams (e.g. team:bitbarg,ali), push it, and print the link
send to file="-":
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{ recipients }}"
    git -C "$dir" pull --quiet --ff-only 2>/dev/null || echo "warning: could not update $dir" >&2
    people=()
    IFS=',' read -ra targets <<<"{{ to }}"
    for t in "${targets[@]}"; do
        if [[ "$t" == team:* ]]; then
            team="$dir/teams/${t#team:}.txt"
            [[ -f "$team" ]] || { echo "unknown team: ${t#team:}" >&2; exit 1; }
            members="$(grep -vE '^[[:space:]]*(#|$)' "$team" || true)"
            [[ -n "$members" ]] || { echo "team ${t#team:} has no members" >&2; exit 1; }
            while read -r name; do people+=("$name"); done <<<"$members"
        else
            people+=("$t")
        fi
    done
    args=()
    names=()
    for p in $(printf '%s\n' "${people[@]}" | sort -u); do
        [[ -f "$dir/people/$p.pub" ]] || { echo "no key for $p; ask them to open {{ base_url }}#setup and send you their public key" >&2; exit 1; }
        args+=(-R "$dir/people/$p.pub")
        names+=("$p")
    done
    id="$(openssl rand -hex 16)"
    if [[ "{{ file }}" == "-" && -t 0 ]]; then
        echo "Paste the secret, then press Ctrl-D:" >&2
    fi
    age "${args[@]}" -o "s/$id.age" "{{ file }}"
    git add "s/$id.age"
    git commit --quiet -m "share: add $id"
    git push --quiet
    echo "{{ base_url }}#$id"
    echo "Readable by: ${names[*]}. Live in about a minute." >&2

# Register a public key someone sent from the #setup page (once per device they use)
add-key name key:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{ name }}" =~ ^[a-z0-9-]+$ ]] || { echo "name must be lowercase letters, digits, and dashes" >&2; exit 1; }
    [[ "{{ key }}" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] || { echo "not an age public key: {{ key }}" >&2; exit 1; }
    dir="{{ recipients }}"
    mkdir -p "$dir/people"
    printf '# added %s\n%s\n' "$(date +%F)" "{{ key }}" >> "$dir/people/{{ name }}.pub"
    git -C "$dir" add "people/{{ name }}.pub"
    git -C "$dir" commit --quiet -m "share: add key for {{ name }}"
    git -C "$dir" push --quiet
    echo "added a key for {{ name }}"

# Add a person to a team
join team name:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{ recipients }}"
    [[ -f "$dir/people/{{ name }}.pub" ]] || echo "warning: {{ name }} has no key yet" >&2
    if grep -qx "{{ name }}" "$dir/teams/{{ team }}.txt" 2>/dev/null; then
        echo "{{ name }} is already in {{ team }}"
        exit 0
    fi
    echo "{{ name }}" >> "$dir/teams/{{ team }}.txt"
    git -C "$dir" add "teams/{{ team }}.txt"
    git -C "$dir" commit --quiet -m "share: add {{ name }} to {{ team }}"
    git -C "$dir" push --quiet
    echo "added {{ name }} to {{ team }}"

# List teams with their members, and people with how many keys each has
recipients:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{ recipients }}"
    echo "teams:"
    for f in "$dir"/teams/*.txt; do
        [[ -e "$f" ]] || continue
        printf '  %-14s %s\n' "$(basename "$f" .txt)" "$(grep -vE '^[[:space:]]*(#|$)' "$f" | paste -sd ' ' - || true)"
    done
    echo "people:"
    for f in "$dir"/people/*.pub; do
        [[ -e "$f" ]] || continue
        printf '  %-14s %s key(s)\n' "$(basename "$f" .pub)" "$(grep -c '^age1' "$f")"
    done

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
    echo 'export { Decrypter, identityToRecipient } from "age-encryption";' > entry.js
    npx esbuild entry.js --bundle --format=esm --minify --outfile="{{ justfile_directory() }}/vendor/age-{{ version }}.js"
