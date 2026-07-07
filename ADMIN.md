# Admin guide — Starface Data for Claude Desktop

For Jason. How to distribute this and grant people access.

## What this is

A **local MCP server** that connects **Claude Desktop** (not Claude Code) to the BigQuery
datalake (`disco-stock-489818-d4`), read-only. Unlike the `starface-bigquery` *plugin* (which
uses Google's remote MCP endpoint and is for Claude Code), this is a stdio server that runs on
the user's Mac and talks to the BigQuery API directly using the user's own gcloud credentials.

- **No keys or secrets are distributed.** Each user authenticates as themselves via
  `gcloud auth application-default login`, bound by their own BigQuery IAM.
- The installer bootstraps everything a non-technical user needs (Homebrew, Node, gcloud),
  runs the Google sign-in, and wires up `claude_desktop_config.json`.

## Distributing it (one-paste command)

Users run a **single Terminal command** — no download, no app, so macOS Gatekeeper never
triggers (a script run via `bash` isn't gated the way a double-clicked app is):

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jasonstarface/starface-data/main/install.sh)"
```

That downloads [`install.sh`](install.sh) from the **public** repo `jasonstarface/starface-data`
and runs it. The script downloads the connector (this repo's tarball), installs Homebrew / Node /
gcloud as needed, signs the user in, and wires up Claude Desktop.

**Why public is fine:** the repo has **no secrets** — auth is each user's own gcloud login, and
the data stays locked behind their BigQuery IAM. The project id is not sensitive on its own.

**To share:** send people the one-paste command (it's in `README.md` and the Setup Guide doc).
Nothing to host on Drive anymore.

### Updating the connector

Edit `src/server.ts` → `npm run build` (regenerates `dist/`, which is committed) → commit & push
to `main`. The command URL never changes; users just re-run it to pick up the new version.

Do **not** commit `node_modules/` — the installer runs `npm install --omit=dev` on each machine.
`dist/` **is** committed (prebuilt) so the installer never has to compile.

### Zero-warning upgrade (optional)

The one-paste flow avoids Gatekeeper entirely. If you'd rather hand people a double-click app
instead, that requires Apple notarization (Apple Developer Program, $99/yr) — otherwise modern
macOS blocks unsigned apps with a Move-to-Trash dialog. The command is the better free option.

## Granting a user access (you do this in GCP once per person)

Grant these roles on project `disco-stock-489818-d4`:

| Role | Why |
|---|---|
| `roles/bigquery.dataViewer` | read table data |
| `roles/bigquery.jobUser` | run queries |
| `roles/serviceusage.serviceUsageConsumer` | lets ADC set the quota/billing project |

Console: **IAM & Admin → IAM → Grant access**, principal = their Google email, add the three
roles. Or by CLI:

```bash
USER="person@starfaceworld.com"
for ROLE in roles/bigquery.dataViewer roles/bigquery.jobUser roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding disco-stock-489818-d4 \
    --member="user:$USER" --role="$ROLE"
done
```

Scope data access further with authorized views / row-level or column-level policies if a user
should only see part of the datalake — the server itself imposes no per-user filtering beyond IAM.

## How it stays read-only

Two layers: (1) users only ever get `dataViewer` + `jobUser` (never `dataEditor`), so BigQuery
rejects writes; (2) the server rejects any statement that isn't `SELECT`/`WITH`, blocks
DDL/DML keywords, and refuses multi-statement scripts. There's also a `maximumBytesBilled` cap
(~50 GB/query) and a 3,000-row result cap.

## Where things land on the user's Mac

- Connector code: `~/.starface-bq-mcp/` (copied from the folder; `dist/` + `node_modules/`)
- Google credentials: `~/.config/gcloud/application_default_credentials.json`
- Claude Desktop config: `~/Library/Application Support/Claude/claude_desktop_config.json`
  (the installer merges in only the `starface-bigquery` entry and keeps a `.bak`)

## Changing the server later

Edit `src/server.ts`, `npm run build`, re-distribute. Users re-run the installer (idempotent);
the config entry and `~/.starface-bq-mcp` are overwritten in place.

## Revoking access

Remove the IAM roles in GCP. (Optional local cleanup on their Mac: delete the
`starface-bigquery` block from `claude_desktop_config.json` and `~/.starface-bq-mcp/`.)

## Dev / testing

```bash
npm install && npm run build
node scripts/smoketest.mjs   # live handshake + query + schema (uses your own ADC)
```
