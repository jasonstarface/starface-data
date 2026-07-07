#!/usr/bin/env node
/**
 * Safely add the "starface-bigquery" server to Claude Desktop's config,
 * preserving every other key. Idempotent. Keeps a .bak of the previous file.
 *
 * Usage:
 *   node merge-config.mjs <nodeBinPath> <serverJsPath> [configPath]
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync, renameSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

const [, , nodeBin, serverJs, configArg] = process.argv;

if (!nodeBin || !serverJs) {
  console.error("Usage: node merge-config.mjs <nodeBinPath> <serverJsPath> [configPath]");
  process.exit(1);
}

const configPath =
  configArg ||
  join(homedir(), "Library", "Application Support", "Claude", "claude_desktop_config.json");

// Load existing config (or start fresh) — tolerate an empty/whitespace file.
let config = {};
if (existsSync(configPath)) {
  const raw = readFileSync(configPath, "utf8").trim();
  if (raw) {
    try {
      config = JSON.parse(raw);
    } catch (err) {
      console.error(`Existing config at ${configPath} is not valid JSON. Aborting to avoid data loss.`);
      console.error(String(err));
      process.exit(1);
    }
  }
  // Back up whatever was there before we touch it.
  copyFileSync(configPath, `${configPath}.bak`);
} else {
  mkdirSync(dirname(configPath), { recursive: true });
}

if (typeof config !== "object" || config === null || Array.isArray(config)) {
  console.error("Existing config is not a JSON object. Aborting.");
  process.exit(1);
}

config.mcpServers = config.mcpServers && typeof config.mcpServers === "object" ? config.mcpServers : {};
config.mcpServers["starface-bigquery"] = {
  command: nodeBin,
  args: [serverJs],
  env: { GOOGLE_CLOUD_PROJECT: "disco-stock-489818-d4" },
};

// Atomic write: temp file then rename over the target.
const tmp = `${configPath}.tmp`;
writeFileSync(tmp, JSON.stringify(config, null, 2) + "\n", "utf8");
renameSync(tmp, configPath);

console.log(`Updated ${configPath}`);
console.log(`  starface-bigquery -> ${nodeBin} ${serverJs}`);
