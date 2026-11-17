import { ApiError } from "./security";

export async function readJsonBody(
  request: Request,
  maximumBytes = 262144,
): Promise<Record<string, unknown>> {
  const advertised = Number(request.headers.get("Content-Length"));
  if (advertised > maximumBytes) throw new ApiError(413, "Dữ liệu quá lớn.");
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, "Thiếu dữ liệu.");
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });
  let bytes = 0,
    raw = "";
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      bytes += next.value.byteLength;
      if (bytes > maximumBytes) {
        await reader.cancel();
        throw new ApiError(413, "Dữ liệu quá lớn.");
      }
      raw += decoder.decode(next.value, { stream: true });
    }
    raw += decoder.decode();
    const body: unknown = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body))
      throw new ApiError(400, "Dữ liệu không hợp lệ.");
    return body as Record<string, unknown>;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "JSON hoặc UTF-8 không hợp lệ.");
  } finally {
    reader.releaseLock();
  }
}
