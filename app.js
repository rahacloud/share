import { Decrypter, identityToRecipient } from "./vendor/age-0.3.1.js";

// Two kinds of links, both carried in the fragment, which is never sent to a
// server, so GitHub only ever sees ciphertext:
//   #<id>.<AGE-SECRET-KEY-1…>  one-off share, the key is in the link
//   #<id>                      shared by name, decrypted with this browser's key
// #setup (or no fragment) creates this browser's key.
const LINK = /^([0-9a-f]{32})(?:\.(AGE-SECRET-KEY-1[0-9A-Z]{58}))?$/;

const $ = (id) => document.getElementById(id);

function show(section) {
  for (const id of ["loading", "ready", "setup", "error"]) {
    $(id).hidden = id !== section;
  }
}

function fail(message, { offerSetup = false } = {}) {
  $("error-message").textContent = message;
  $("error-setup").hidden = !offerSetup;
  show("error");
}

function flash(button, text) {
  const original = button.textContent;
  button.textContent = text;
  setTimeout(() => (button.textContent = original), 2000);
}

// This browser's X25519 private key lives in IndexedDB as a non-extractable
// CryptoKey: pages on this origin can decrypt with it but never read it.
function store(mode, fn) {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open("share", 1);
    open.onupgradeneeded = () => open.result.createObjectStore("keys");
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const tx = open.result.transaction("keys", mode);
      const req = fn(tx.objectStore("keys"));
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error);
    };
  });
}

const loadKey = () => store("readonly", (s) => s.get("identity"));
const saveKey = (key) => store("readwrite", (s) => s.put(key, "identity"));

async function createKey() {
  const { privateKey } = await crypto.subtle.generateKey({ name: "X25519" }, false, ["deriveBits"]);
  await saveKey(privateKey);
  // Ask the browser not to evict the key under storage pressure.
  await navigator.storage?.persist?.();
  return privateKey;
}

async function showPublicKey(key) {
  $("public-key").textContent = await identityToRecipient(key);
  $("setup-new").hidden = true;
  $("setup-done").hidden = false;
}

async function setup() {
  const key = await loadKey();
  if (key) await showPublicKey(key);
  show("setup");
}

$("create").addEventListener("click", async () => {
  try {
    await showPublicKey(await createKey());
  } catch (err) {
    fail(`Could not create a key: ${err.message}. Try an up-to-date Chrome, Firefox, or Safari.`);
  }
});
$("copy-public").addEventListener("click", async () => {
  await navigator.clipboard.writeText($("public-key").textContent);
  flash($("copy-public"), "Copied");
});
// Replacing needs a second click, since it orphans every secret shared with the old key.
let armed = false;
$("replace").addEventListener("click", async () => {
  if (!armed) {
    armed = true;
    $("replace").textContent = "Click again to replace";
    return;
  }
  armed = false;
  $("replace").textContent = "Replace key";
  await showPublicKey(await createKey());
});

async function reveal(id, linkKey) {
  const key = linkKey ?? (await loadKey());
  if (!key) {
    fail("This secret was shared with specific people, and this browser has no key yet.", { offerSetup: true });
    return;
  }

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
    if (linkKey) {
      fail("This link's key does not match the secret. Ask the sender for the full link.");
    } else {
      fail("This secret was not shared with this browser's key. Open it on the browser you set up, or send this browser's public key to RahaCloud.", { offerSetup: true });
    }
    return;
  }

  $("secret").textContent = secret;
  show("ready");
}

$("reveal").addEventListener("click", () => {
  const concealed = $("secret").classList.toggle("concealed");
  $("reveal").textContent = concealed ? "Reveal" : "Hide";
});
$("copy").addEventListener("click", async () => {
  await navigator.clipboard.writeText($("secret").textContent);
  flash($("copy"), "Copied");
});

async function route() {
  const hash = decodeURIComponent(location.hash.slice(1)).trim();
  if (hash === "" || hash === "setup") {
    await setup();
    return;
  }

  const match = LINK.exec(hash);
  if (!match) {
    fail("This link is incomplete. Ask the sender for the full link.");
    return;
  }
  const [, id, linkKey] = match;
  if (linkKey) {
    // Drop the key from the address bar and from this tab's history entry.
    history.replaceState(null, "", location.pathname);
  }
  await reveal(id, linkKey);
}

const run = () => route().catch((err) => fail(`Something went wrong: ${err.message}`));
window.addEventListener("hashchange", run);
run();
