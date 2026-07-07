#!/usr/bin/env node
/**
 * Starface BigQuery — local MCP server for Claude Desktop.
 *
 * Read-only access to the Starface datalake (disco-stock-489818-d4) using the
 * signed-in user's Google Application Default Credentials (ADC). No keys, no
 * shared secrets — each person is bound by their own BigQuery IAM permissions.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { BigQuery } from "@google-cloud/bigquery";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Config — the project is hardcoded so the tool can only ever read Starface data.
// ---------------------------------------------------------------------------
const PROJECT_ID = "disco-stock-489818-d4";
const MAX_ROWS = 3000; // matches the row cap of the existing BigQuery connector
const MAX_BYTES_BILLED = String(50 * 1024 * 1024 * 1024); // 50 GB cost guard
const QUERY_TIMEOUT_MS = 170_000; // stay under Claude Desktop's tool timeout

const bq = new BigQuery({ projectId: PROJECT_ID });

// ---------------------------------------------------------------------------
// Read-only guard. IAM already blocks writes (users get dataViewer + jobUser,
// never dataEditor), but we reject non-SELECT statements up front so mistakes
// fail fast with a clear message instead of a BigQuery permission error.
// ---------------------------------------------------------------------------
const FORBIDDEN = /\b(INSERT|UPDATE|DELETE|MERGE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|REPLACE|CALL|EXPORT|LOAD|BEGIN|COMMIT)\b/i;

function stripSqlNoise(sql: string): string {
  return sql
    .replace(/--[^\n]*/g, " ") // line comments
    .replace(/\/\*[\s\S]*?\*\//g, " ") // block comments
    .replace(/'(?:[^'\\]|\\.)*'/g, "''") // string literals
    .replace(/"(?:[^"\\]|\\.)*"/g, '""') // quoted identifiers/strings
    .trim();
}

function assertReadOnly(sql: string): void {
  const cleaned = stripSqlNoise(sql);
  if (!cleaned) throw new Error("Empty query.");

  // No stacked statements (allow a single trailing semicolon).
  if (cleaned.replace(/;\s*$/, "").includes(";")) {
    throw new Error("Only a single SELECT statement is allowed (no multiple statements).");
  }

  const firstWord = cleaned.match(/^\(*\s*([a-zA-Z]+)/)?.[1]?.toUpperCase();
  if (firstWord !== "SELECT" && firstWord !== "WITH") {
    throw new Error(
      `Read-only: only SELECT / WITH queries are allowed (got "${firstWord ?? "?"}").`
    );
  }

  if (FORBIDDEN.test(cleaned)) {
    throw new Error("Read-only: statement contains a write/DDL keyword and was blocked.");
  }
}

function friendlyError(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  if (/permission|denied|Access Denied|forbidden|403/i.test(msg)) {
    return (
      `BigQuery denied this request. Your Google account needs read access to the ` +
      `Starface datalake (project ${PROJECT_ID}). Ask Jason (jason@starfaceworld.com) ` +
      `to grant BigQuery Data Viewer + Job User.\n\nDetails: ${msg}`
    );
  }
  if (/could not load the default credentials|Application Default Credentials|reauth|invalid_grant/i.test(msg)) {
    return (
      `Not signed in to Google. Re-run the "Install Starface Data" app, or run ` +
      `\`gcloud auth application-default login\` in Terminal.\n\nDetails: ${msg}`
    );
  }
  return msg;
}

// ---------------------------------------------------------------------------
// Server + tools
// ---------------------------------------------------------------------------
const server = new McpServer({
  name: "starface-bigquery",
  version: "1.0.0",
});

const HOUSE_RULES =
  "Starface data conventions: start with `mart.*` tables (mart.orders is the canonical " +
  "revenue source across all channels). ALWAYS filter by `date` (most tables are large and " +
  "partitioned by date). Use SAFE_DIVIDE instead of / for rate metrics. Do NOT mix revenue " +
  "sources — mart.orders is truth; ad_reported_revenue is platform-attributed (inflated). " +
  "raw.ALLOY_DATA is 176M rows — always date-filter it. Fully-qualify tables as " +
  "`disco-stock-489818-d4.<dataset>.<table>` or use just `<dataset>.<table>`.";

server.registerTool(
  "list_datasets",
  {
    title: "List datasets",
    description: `List all BigQuery datasets in the Starface project (${PROJECT_ID}). Key ones: mart (materialized analytics — use these), intermediate & staging (views), raw (source feeds), lookup (SKU taxonomy).`,
    inputSchema: {},
  },
  async () => {
    try {
      const [datasets] = await bq.getDatasets();
      const ids = datasets.map((d) => d.id).filter(Boolean).sort();
      return { content: [{ type: "text", text: ids.join("\n") }] };
    } catch (err) {
      return { isError: true, content: [{ type: "text", text: friendlyError(err) }] };
    }
  }
);

server.registerTool(
  "list_tables",
  {
    title: "List tables",
    description: "List all tables/views in a dataset. e.g. dataset='mart' for the main analytics tables (orders, daily_channel_performance, paid_media, ...).",
    inputSchema: { dataset: z.string().describe("Dataset id, e.g. 'mart'") },
  },
  async ({ dataset }) => {
    try {
      const [tables] = await bq.dataset(dataset).getTables();
      const ids = tables.map((t) => t.id).filter(Boolean).sort();
      return { content: [{ type: "text", text: ids.join("\n") || `(no tables in ${dataset})` }] };
    } catch (err) {
      return { isError: true, content: [{ type: "text", text: friendlyError(err) }] };
    }
  }
);

server.registerTool(
  "describe_table",
  {
    title: "Describe table",
    description: "Show a table's columns and types, row count, and partition/cluster fields. Call this before writing a query so you use real column names and know how to filter by date.",
    inputSchema: {
      dataset: z.string().describe("Dataset id, e.g. 'mart'"),
      table: z.string().describe("Table id, e.g. 'orders'"),
    },
  },
  async ({ dataset, table }) => {
    try {
      const [metadata] = await bq.dataset(dataset).table(table).getMetadata();
      const fields: Array<{ name: string; type: string; mode?: string }> =
        metadata.schema?.fields ?? [];
      const lines = fields.map(
        (f) => `  ${f.name}: ${f.type}${f.mode && f.mode !== "NULLABLE" ? ` (${f.mode})` : ""}`
      );
      const out = [
        `${dataset}.${table}`,
        metadata.numRows != null ? `rows: ${Number(metadata.numRows).toLocaleString()}` : null,
        metadata.timePartitioning?.field
          ? `partitioned by: ${metadata.timePartitioning.field}`
          : metadata.timePartitioning
          ? `partitioned by: _PARTITIONTIME`
          : null,
        metadata.clustering?.fields?.length
          ? `clustered by: ${metadata.clustering.fields.join(", ")}`
          : null,
        "",
        "columns:",
        ...lines,
      ]
        .filter((l) => l !== null)
        .join("\n");
      return { content: [{ type: "text", text: out }] };
    } catch (err) {
      return { isError: true, content: [{ type: "text", text: friendlyError(err) }] };
    }
  }
);

server.registerTool(
  "query",
  {
    title: "Run a read-only SQL query",
    description:
      `Run a read-only (SELECT/WITH) BigQuery Standard SQL query against the Starface datalake and get rows back (capped at ${MAX_ROWS} rows). ` +
      HOUSE_RULES,
    inputSchema: {
      sql: z.string().describe("A single read-only SELECT/WITH query in BigQuery Standard SQL."),
    },
  },
  async ({ sql }) => {
    try {
      assertReadOnly(sql);
      const [job] = await bq.createQueryJob({
        query: sql,
        useLegacySql: false,
        maximumBytesBilled: MAX_BYTES_BILLED,
        jobTimeoutMs: QUERY_TIMEOUT_MS,
      });
      const [rows] = await job.getQueryResults({ maxResults: MAX_ROWS });
      if (!rows.length) {
        return { content: [{ type: "text", text: "Query ran successfully — 0 rows." }] };
      }
      const truncated = rows.length >= MAX_ROWS;
      const body = JSON.stringify(rows, null, 2);
      const note = truncated
        ? `\n\n(Showing the first ${MAX_ROWS} rows — add aggregation or a tighter date filter to narrow results.)`
        : "";
      return { content: [{ type: "text", text: `${rows.length} row(s):\n${body}${note}` }] };
    } catch (err) {
      return { isError: true, content: [{ type: "text", text: friendlyError(err) }] };
    }
  }
);

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // stderr is safe for logs; stdout is the MCP protocol channel.
  console.error(`[starface-bigquery] MCP server ready (project ${PROJECT_ID}, read-only).`);
}

main().catch((err) => {
  console.error("[starface-bigquery] fatal:", err);
  process.exit(1);
});
