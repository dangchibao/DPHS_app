import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { randomBytes, randomUUID, pbkdf2Sync } from "node:crypto";
import { build } from "esbuild";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const option = (key) => {
  const index = args.indexOf(key);
  return index < 0 ? undefined : args[index + 1];
};

async function main() {
  const configPath = option("--config");
  if (!configPath) throw new Error("PROVISION_CONFIG_REQUIRED");
  const config = JSON.parse(readFileSync(resolve(root, configPath), "utf8"));
  const account = config.account_id;
  const database = config.d1_databases?.find((d) => d.binding === "DB");
  if (
    !/^[a-f0-9]{32}$/.test(account ?? "") ||
    !/^[a-f0-9-]{36}$/.test(database?.database_id ?? "") ||
    database.database_id === "00000000-0000-0000-0000-000000000000" ||
    config.vars?.ENVIRONMENT !== "production"
  )
    throw new Error("PROVISION_CONFIG_INVALID");
  const execute = args.includes("--execute-cloud");
  if (execute && option("--confirm-empty-database") !== database.database_id)
    throw new Error("PROVISION_CONFIRM_REQUIRED");
  const password = process.env.PROVISION_OWNER_PASSWORD;
  if (
    typeof password !== "string" ||
    password.length < 16 ||
    password.length > 200
  )
    throw new Error("PROVISION_PASSWORD_ENV_REQUIRED");
  const salt = randomBytes(32).toString("hex");
  const input = {
    userId: randomUUID(),
    storeId: "store-cn01",
    deviceId: "device-owner-web",
    assignmentId: randomUUID(),
    username: "admin",
    storeCode: "NT-CN01",
    storeName: "Ngọc Thanh · Chi nhánh 01",
    salt,
    credential: pbkdf2Sync(
      password,
      Buffer.from(salt, "utf8"),
      600000,
      32,
      "sha256",
    ).toString("hex"),
  };
  if (!execute) {
    console.log(
      JSON.stringify({
        mode: "preview",
        changes: false,
        database_id: database.database_id,
        username: input.username,
        store_id: input.storeId,
        device_id: input.deviceId,
      }),
    );
    return;
  }
  // Token stays in memory and is never passed in shell arguments, persisted,
  // echoed, or attached to arbitrary/redirected URLs.
  const auth = process.env.CLOUDFLARE_API_TOKEN
    ? { token: process.env.CLOUDFLARE_API_TOKEN }
    : JSON.parse(
        execFileSync(
          process.execPath,
          [
            resolve(root, "node_modules/wrangler/bin/wrangler.js"),
            "auth",
            "token",
            "--json",
          ],
          { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
        ),
      );
  if (typeof auth.token !== "string" || !auth.token)
    throw new Error("PROVISION_AUTH_REQUIRED");
  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${account}/d1/database/${database.database_id}`;
  const request = async (suffix, body) => {
    const response = await fetch(endpoint + suffix, {
      method: body ? "POST" : "GET",
      redirect: "error",
      signal: AbortSignal.timeout(30000),
      headers: {
        Authorization: `Bearer ${auth.token}`,
        "Content-Type": "application/json",
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const result = await response.json();
    if (!response.ok || result.success !== true)
      throw new Error("PROVISION_CLOUD_QUERY_FAILED");
    return result.result;
  };
  const info = await request("");
  if (info.name !== database.database_name)
    throw new Error("PROVISION_DATABASE_NAME");
  const query = async (body) => {
    // Deliberately no retry: a lost response to a write requires inspection.
    const result = await request("/query", body);
    if (!Array.isArray(result) || result.some((r) => r.success !== true))
      throw new Error("PROVISION_CLOUD_QUERY_FAILED");
    return result;
  };
  const prepare = (sql, params = []) => ({
    sql,
    params,
    bind(...values) {
      return prepare(sql, values);
    },
    async first() {
      return (await query({ sql, params }))[0].results[0] ?? null;
    },
    async all() {
      return (await query({ sql, params }))[0];
    },
  });
  const db = {
    prepare,
    async batch(statements) {
      const batch = statements.map(({ sql, params }) => ({ sql, params }));
      const results = await query({ batch });
      if (results.length !== batch.length)
        throw new Error("PROVISION_CLOUD_QUERY_FAILED");
      return results;
    },
  };
  const compiled = await build({
    entryPoints: [resolve(root, "src/provision_owner.ts")],
    bundle: true,
    write: false,
    platform: "node",
    format: "esm",
    target: "node24",
    logLevel: "silent",
  });
  const { provisionOwner } = await import(
    `data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString("base64")}`
  );
  const receipt = await provisionOwner(db, input);
  console.log(
    JSON.stringify({
      mode: "provisioned",
      database_id: database.database_id,
      ...receipt,
    }),
  );
}
main().catch((error) => {
  const safe = /^PROVISION_[A-Z_]+$/.test(error?.message ?? "")
    ? error.message
    : "PROVISION_FAILED";
  console.error(
    JSON.stringify({ error: safe, changed: "not-confirmed-if-response-lost" }),
  );
  process.exitCode = 1;
});
