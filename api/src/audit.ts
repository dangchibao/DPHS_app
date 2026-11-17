import type { Actor } from "./auth";
import { sha256 } from "./security";
import { redactAuditChanges } from "./audit_redaction";

/** Client chains use positive indices; API chains use negative indices per device.
 * This avoids racing a disconnected device's hash chain. Both are append-only.
 */
export async function auditStatement(
  db: D1Database,
  actor: Omit<Actor, "session_id" | "name">,
  action: string,
  entity: string,
  reason: string,
  changes: Record<string, unknown> = {},
  documentCode: string | null = null,
): Promise<D1PreparedStatement> {
  changes = redactAuditChanges(changes, action);
  const previous = await db
    .prepare(
      "SELECT hash,chain_index FROM audit_logs WHERE store_id=? AND device_id=? AND chain_index<0 ORDER BY chain_index ASC LIMIT 1",
    )
    .bind(actor.store_id, actor.device_id)
    .first<{ hash: string; chain_index: number }>();
  const id = crypto.randomUUID(),
    now = new Date().toISOString(),
    index = (previous?.chain_index ?? 0) - 1;
  const documentAction = [
    "INVOICE_SYNC",
    "PAYMENT_SYNC",
    "TAILOR_SYNC",
    "RETURN_SYNC",
    "RESERVATION_SYNC",
    "TRANSFER_SYNC",
    "TRANSFER_DISPATCH_SYNC",
  ].includes(action);
  const document =
    documentAction && !documentCode
      ? await db
          .prepare("SELECT code FROM documents WHERE store_id=? AND id=?")
          .bind(actor.store_id, entity)
          .first<{ code: string }>()
      : null;
  const entityType = documentAction
    ? "document"
    : action.startsWith("DEVICE_")
      ? "device"
      : action.startsWith("STORE_")
        ? "store"
        : "user";
  const payload = {
    id,
    store_id: actor.store_id,
    device_id: actor.device_id,
    user_id: actor.user_id || null,
    role: actor.role,
    action,
    entity_type: entityType,
    entity_id: entity,
    changes,
    reason,
    client_time: now,
    severity: "sensitive",
    hash_prev: previous?.hash ?? "",
    chain_index: index,
  };
  const hash = await sha256(JSON.stringify(payload));
  return db
    .prepare(
      "INSERT INTO audit_logs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    )
    .bind(
      id,
      actor.store_id,
      actor.device_id,
      actor.user_id || null,
      actor.role,
      action,
      entityType,
      entity,
      documentCode ?? document?.code ?? null,
      JSON.stringify(changes),
      reason,
      now,
      now,
      "0.5.0",
      "sensitive",
      previous?.hash ?? "",
      hash,
      index,
    );
}
