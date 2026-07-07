// Resolve a download URL for a standalone, relocatable Python build
// (python-build-standalone) matching the given macOS arch. Used by install.sh
// only when we must supply a Python for gcloud (no system Python present).
//
//   node pick-python-asset.mjs <aarch64-apple-darwin|x86_64-apple-darwin>
//
// Prints the browser_download_url on success; exits non-zero otherwise.
import https from "node:https";

const arch = process.argv[2];
if (!arch) process.exit(64);

// gcloud supports 3.9–3.13; prefer well-tested 3.12, fall back across the range.
const PREFS = ["cpython-3.12.", "cpython-3.11.", "cpython-3.13.", "cpython-3.10."];
const API = "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest";

https
  .get(API, { headers: { "User-Agent": "starface-data-installer", Accept: "application/vnd.github+json" } }, (res) => {
    let d = "";
    res.on("data", (c) => (d += c));
    res.on("end", () => {
      try {
        const assets = (JSON.parse(d).assets || []);
        for (const p of PREFS) {
          const a = assets.find(
            (x) => x.name.includes(p) && x.name.includes(arch) && x.name.endsWith("install_only.tar.gz")
          );
          if (a) {
            console.log(a.browser_download_url);
            return;
          }
        }
        process.exit(2); // no matching asset
      } catch {
        process.exit(3); // bad JSON
      }
    });
  })
  .on("error", () => process.exit(4)); // network error
