import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { randomBytes, pbkdf2Sync } from "node:crypto";
import { execFileSync } from "node:child_process";

async function main() {
  const args = process.argv.slice(2),
    index = args.indexOf("--config");
  if (index < 0 || !args.includes("--execute-cloud"))
    throw new Error("E2E_EXPLICIT_CONFIG_REQUIRED");
  const config = JSON.parse(readFileSync(resolve(args[index + 1]), "utf8"));
  if (
    config.name !== "ngoc-thanh-pos-e2e" ||
    config.d1_databases?.[0]?.database_name !== "ngoc-thanh-pos-e2e" ||
    config.vars?.ALLOWED_ORIGIN !==
      "https://ngoc-thanh-pos-e2e.ngoc-thanh-161df6.workers.dev"
  )
    throw new Error("E2E_ISOLATED_TARGET_REQUIRED");
  const origin = config.vars.ALLOWED_ORIGIN;
  const request = async (path, body, token) => {
    const r = await fetch(origin + path, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(30000),
      headers: {
        "Content-Type": "application/json",
        "X-Client-Schema": "30",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
    });
    const result = await r.json();
    if (!r.ok)
      throw new Error("E2E_HTTP_" + r.status + "_" + (result.code ?? "FAILED"));
    return result;
  };
  if (args.includes("--finish")) {
    const context = JSON.parse(process.env.NT_CLOUD_E2E_CONFIG ?? "{}");
    if (context.origin !== origin) throw new Error("E2E_CONTEXT_REQUIRED");
    for (const device of [context.a, context.b])
      await request(
        "/management",
        {
          action: "set_device",
          store_id: context.storeId,
          id: device.id,
          status: "revoked",
          reason: "Hoàn tất kiểm thử cloud E2E riêng",
        },
        context.adminToken,
      );
    await request("/auth/logout", {}, context.adminToken);
    const auth = JSON.parse(
      execFileSync(
        process.execPath,
        ["node_modules/wrangler/bin/wrangler.js", "auth", "token", "--json"],
        { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
      ),
    );
    const r = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${config.account_id}/workers/scripts/${config.name}/subdomain`,
      {
        method: "POST",
        redirect: "error",
        headers: {
          Authorization: `Bearer ${auth.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ enabled: false, previews_enabled: false }),
      },
    );
    const result = await r.json();
    if (!r.ok || !result.success) throw new Error("E2E_DISABLE_FAILED");
    console.log(
      JSON.stringify({
        qaDevicesRevoked: true,
        adminLoggedOut: true,
        publicEndpointDisabled: true,
      }),
    );
    return;
  }
  const password = process.env.PROVISION_OWNER_PASSWORD;
  if (!password || password.length < 16)
    throw new Error("E2E_PASSWORD_ENV_REQUIRED");
  const challenge = await request("/auth/challenge", { username: "admin" });
  const login = await request("/auth/web/login", {
    username: "admin",
    credential: pbkdf2Sync(
      password,
      challenge.salt,
      600000,
      32,
      "sha256",
    ).toString("hex"),
    store_id: "store-cn01",
    device_id: "device-owner-web",
    installation_id: "e2e-controller-" + config.d1_databases[0].database_id,
  });
  function uuid7() {
    const bytes = randomBytes(16);
    bytes.writeUIntBE(Date.now(), 0, 6);
    bytes[6] = (bytes[6] & 15) | 112;
    bytes[8] = (bytes[8] & 63) | 128;
    const h = bytes.toString("hex");
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }
  const devices = [];
  for (const code of ["QA", "QB"]) {
    const id = uuid7();
    const invite = await request(
      "/management",
      {
        action: "invite_device",
        store_id: "store-cn01",
        id,
        enrollment_id: uuid7(),
        code: code + randomBytes(3).toString("hex").toUpperCase(),
        name: `Thiết bị cloud E2E ${code}`,
        kind: "native",
        reason: "Kiểm thử offline và lost ACK trên QA riêng",
      },
      login.token,
    );
    devices.push({
      id,
      token: invite.token,
      installation: "e2e-native-" + randomBytes(24).toString("hex"),
    });
  }
  // Only the parent process captures this stdout into an environment variable;
  // it contains short-lived QA tokens and must not be logged or persisted.
  console.log(
    JSON.stringify({
      origin,
      storeId: "store-cn01",
      adminToken: login.token,
      a: devices[0],
      b: devices[1],
    }),
  );
}
main().catch(() => {
  console.error("E2E_SETUP_OR_CLEANUP_FAILED");
  process.exitCode = 1;
});
