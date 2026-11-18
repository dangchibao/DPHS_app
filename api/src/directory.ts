import { clientAuditHead } from "./audit";
import type { Actor } from "./auth";
import { rolePermissions } from "./security";
import { staffFreezeCondition } from "./staff_handoffs";
export async function directory(
  db: D1Database,
  actor: Actor,
  mediaEnabled = false,
): Promise<Response> {
  const [stores, devices, users] = await db.batch([
    db.prepare("SELECT * FROM stores WHERE id=?").bind(actor.store_id),
    db.prepare("SELECT * FROM devices WHERE store_id=?").bind(actor.store_id),
    db
      .prepare(
        `SELECT u.id,u.username,u.display_name,u.active,u.must_change_password,u.updated_at,a.role,a.active AS assignment_active,${staffFreezeCondition("u.id", "a.store_id")} AS frozen
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
          "SELECT s.id AS store_id,s.code AS store_code,s.name AS store_name,d.id AS device_id,d.code AS device_code,d.name AS device_name FROM stores s JOIN devices d ON d.store_id=s.id WHERE s.active=1 AND d.status='approved' AND d.kind='native' AND s.id<>? ORDER BY s.code,d.code",
        )
        .bind(actor.store_id)
        .all()
    : null;
  const auditHead = await clientAuditHead(db, actor.store_id, actor.device_id);
  return Response.json({
    audit_head: auditHead,
    handoffs: (
      await db
        .prepare(
          "SELECT h.id,h.user_id,EXISTS(SELECT 1 FROM staff_change_devices d WHERE d.store_id=? AND d.device_id=? AND d.request_id=h.id AND d.acked_at IS NULL) AS requires_ack FROM staff_change_requests h WHERE h.status='pending' AND EXISTS(SELECT 1 FROM json_each(h.scope_json) WHERE value=?)",
        )
        .bind(actor.store_id, actor.device_id, actor.store_id)
        .all()
    ).results,
    media_enabled: mediaEnabled,
    schema_version: 30,
    stores: stores.results,
    devices: devices.results,
    users: users.results,
    transfer_targets: canStock ? (targets?.results ?? []) : undefined,
  });
}
