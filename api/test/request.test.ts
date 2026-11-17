import { expect, it } from "vitest";
import { readJsonBody } from "../src/request";

it("Chặn body theo byte UTF-8 và dừng stream ngay khi vượt hạn", async () => {
  const request = new Request("https://test", {
    method: "POST",
    body: JSON.stringify({ text: "á".repeat(30) }),
  });
  await expect(readJsonBody(request, 50)).rejects.toMatchObject({
    status: 413,
  });
  expect(
    await readJsonBody(
      new Request("https://test", { method: "POST", body: '{"text":"Áo"}' }),
    ),
  ).toEqual({ text: "Áo" });
  for (const body of ["[]", "null", "{"]) {
    await expect(
      readJsonBody(new Request("https://test", { method: "POST", body })),
    ).rejects.toMatchObject({ status: 400 });
  }
});
