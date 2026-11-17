import type { Actor } from "./auth";
import { rolePermissions } from "./security";
export async function directory(
  db: D1Database,
  actor: Actor,
): Promise<Response> {
  const [stores, devices, users] = await db.batch([
    db.prepare("SELECT * FROM stores WHERE id=?").bind(actor.store_id),
    db.prepare("SELECT * FROM devices WHERE store_id=?").bind(actor.store_id),
    db
      .prepare(
        `SELECT u.id,u.username,u.display_name,u.active,u.must_change_password,u.updated_at,a.role,a.active AS assignment_active
    FROM users u JOIN employee_store_assignments a ON a.user_id=u.id WHERE a.store_id=?`,
      )
      .bind(actor.store_id),
  ]);
  const canStock =
    rolePermissions[actor.role].includes("stock") &&
    rolePermissions[actor.issued_role ?? actor.role].includes("stock");
  const targets = canStock
    ? await db
        .prepare(
          "SELECT s.id AS store_id,s.code AS store_code,s.name AS store_name,d.id AS device_id,d.code AS device_code,d.name AS device_name FROM stores s JOIN devices d ON d.store_id=s.id WHERE s.active=1 AND d.status='approved' AND s.id<>? ORDER BY s.code,d.code",
        )
        .bind(actor.store_id)
        .all()
    : null;
  return Response.json({
    schema_version: 22,
    stores: stores.results,
    devices: devices.results,
    users: users.results,
    transfer_targets: canStock ? (targets?.results ?? []) : undefined,
  });
}
