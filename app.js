import { Decrypter } from "./vendor/age-0.3.1.js";

// Links look like https://rahacloud.com/share/#<id>.<AGE-SECRET-KEY-1…>.
// The fragment is never sent to a server, so GitHub only ever sees ciphertext.
const LINK = /^([0-9a-f]{32})\.(AGE-SECRET-KEY-1[0-9A-Z]{58})$/;

const $ = (id) => document.getElementById(id);

function show(section) {
  for (const id of ["loading", "ready", "error"]) {
    $(id).hidden = id !== section;
  }
}

function fail(message) {
  $("error-message").textContent = message;
  show("error");
}

async function main() {
  const match = LINK.exec(decodeURIComponent(location.hash.slice(1)).trim());
  // Drop the key from the address bar and from this tab's history entry.
  history.replaceState(null, "", location.pathname);

  if (!match) {
    fail("This link is incomplete. Ask the sender for the full link.");
    return;
  }
  const [, id, key] = match;

  const response = await fetch(`s/${id}.age`, { cache: "no-store" });
  if (response.status === 404) {
    fail("This secret has expired or was revoked. Ask the sender to share it again.");
    return;
  }
  if (!response.ok) {
    fail(`Could not fetch the secret (HTTP ${response.status}). Try again in a minute.`);
    return;
  }

  const decrypter = new Decrypter();
  decrypter.addIdentity(key);
  let secret;
  try {
    secret = await decrypter.decrypt(new Uint8Array(await response.arrayBuffer()), "text");
  } catch {
    fail("This link's key does not match the secret. Ask the sender for the full link.");
    return;
  }

  $("secret").textContent = secret;
  $("reveal").addEventListener("click", () => {
    const concealed = $("secret").classList.toggle("concealed");
    $("reveal").textContent = concealed ? "Reveal" : "Hide";
  });
  $("copy").addEventListener("click", async () => {
    await navigator.clipboard.writeText(secret);
    $("copy").textContent = "Copied";
    setTimeout(() => ($("copy").textContent = "Copy"), 2000);
  });
  show("ready");
}

main().catch((err) => fail(`Something went wrong: ${err.message}`));
