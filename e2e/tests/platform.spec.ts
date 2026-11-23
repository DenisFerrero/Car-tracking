import { expect, test, type Page } from "@playwright/test";
import { clickCanvas, fill, nextStep, open, press, semantics, t, tap, totp, type } from "./support.ts";

// The platform from the browser, as a user goes through it: the invite of the first
// administrator (password, authenticator app, recovery codes), a vehicle, its refuels and
// the real consumption, a polygon area, the summary of the month, logout and login with the
// second factor. The steps follow each other on the same account.

const PASSWORD = "e2e-Password-2026!";
const EMAIL = "admin@e2e.invalid";

test.describe.configure({ mode: "serial" });

let page: Page;
let secret = "";
let vehicle = 0;

test.beforeAll(async ({ browser }) => {
	page = await browser.newPage();
});
test.afterAll(async () => {
	await page.close();
});

test("invite: password, authenticator app, recovery codes", async () => {
	const invite = new URL(process.env.INVITE_URL!);
	await open(page, invite.hash.slice(1));
	await expect(page.getByText(t("welcome", { name: "Amministratore" }))).toBeVisible();
	await fill(page, t("newPassword"), PASSWORD);
	await fill(page, t("repeatPassword"), PASSWORD);

	// The secret of the authenticator from the answer of the backend, as an app scans the QR
	const enrollment = page.waitForResponse(response => response.url().endsWith("/api/auth/enroll/start"));
	await tap(page, t("continueLabel"));
	secret = ((await (await enrollment).json()) as { secret: string }).secret;
	await expect(page.getByRole("button", { name: t("activate") })).toBeVisible();
	await type(page, page.getByRole("textbox", { name: "000000" }), totp(secret));
	await tap(page, t("activate"));

	await expect(page.getByText(t("recoveryTitle"))).toBeVisible();
	await page.getByRole("checkbox", { name: t("codesSaved") }).click();
	await tap(page, t("later"));
	await expect(page.getByRole("button", { name: t("navMap") })).toBeVisible();
});

test("vehicle without a tracker, from the devices", async () => {
	await page.getByRole("button", { name: t("navDevices") }).click();
	await page.getByRole("button", { name: t("add") }).click();
	await page.getByRole("button", { name: new RegExp(t("vehicleOption")) }).click();
	await fill(page, t("vehicleName"), "Panda e2e");
	const created = page.waitForResponse(response => response.url().endsWith("/api/vehicles") && response.request().method() === "POST");
	await tap(page, t("addVehicle"));
	vehicle = ((await (await created).json()) as { id: number }).id;
	expect(vehicle).toBeGreaterThan(0);
	await expect(page.getByText("Panda e2e").first()).toBeVisible();
});

test("refuels: two full tanks give the real consumption", async () => {
	await open(page, `/devices/${vehicle}/refuels`);
	await expect(page.getByText(t("noRefuels"))).toBeVisible();
	for (const [litres, cost, odometer] of [["30", "57", "10000"], ["40", "76", "10500"]] as const) {
		await page.getByRole("button", { name: t("addRefuel") }).click();
		await fill(page, t("refuelLitres"), litres);
		await fill(page, t("refuelCost"), cost);
		await fill(page, t("refuelOdometer"), odometer);
		await tap(page, t("save"));
		await expect(page.getByText(t("refuelSaved")).first()).toBeVisible();
	}
	// 40 litres over 500 km, at 1.90 €/l
	await expect(page.getByText(t("realConsumption", { value: "8,0 l/100 km" }))).toBeVisible();
	await expect(page.getByRole("button", { name: /40 l · 76,00 € 1,900 €\/l · 10\.500 km/ })).toBeVisible();
});

test("polygon area drawn on the map", async () => {
	await open(page, `/devices/${vehicle}?tab=3`);
	await page.getByRole("button", { name: t("addArea") }).click();
	await press(page.getByRole("button", { name: t("areaPolygon") }));
	await expect(page.getByText(t("tapMapToDraw"))).toBeVisible();
	// Four corners on the map, around its center
	const map = (await page.locator('[aria-label="flutter_map"]').boundingBox())!;
	const center = { x: map.x + map.width / 2, y: map.y + map.height / 2 };
	await clickCanvas(page, [[-80, -50], [80, -50], [60, 60], [-60, 60]].map(([dx, dy]) => ({ x: center.x + dx!, y: center.y + dy! })));
	await expect(page.getByText(t("areaVertices", { n: 4 }))).toBeVisible();
	await fill(page, t("areaName"), "Quartiere");
	const saved = page.waitForResponse(response => response.url().endsWith(`/api/devices/${vehicle}/geofences`) && response.request().method() === "POST");
	await page.getByRole("button", { name: t("save") }).click();
	const response = await saved;
	expect(response.status(), `${await response.text()} ${response.request().postData()}`).toBe(200);
	expect((response.request().postDataJSON() as { polygon: [number, number][] }).polygon).toHaveLength(4);
	await expect(page.getByRole("button", { name: new RegExp(`^Quartiere ${t("areaPolygonSummary", { n: 4, state: "" }).split(" · ")[0]}`) })).toBeVisible();
});

test("summary of the month from the account", async () => {
	await page.getByRole("button", { name: t("navAccount") }).click();
	await page.getByRole("button", { name: new RegExp(t("monthlySummary")) }).first().click();
	await expect(page.getByRole("button", { name: t("previousMonth") })).toBeVisible();
	// The month just ended has no refuels; the current one the two of the vehicle
	await page.getByRole("button", { name: t("nextMonth") }).click();
	await expect(page.getByText(t("summaryPartial"))).toBeVisible();
	await expect(page.getByRole("button", { name: /Panda e2e/ })).toContainText(t("summaryRefuels", { n: 2, value: "133,00 €" }));
});

test("logout, then login with password and the second factor", async () => {
	await open(page, "/account");
	await page.getByRole("button", { name: new RegExp(t("logout")) }).last().click();
	await expect(page.getByLabel(t("emailLabel"), { exact: true })).toBeVisible();
	await fill(page, t("emailLabel"), EMAIL);
	await fill(page, t("passwordLabel"), PASSWORD);
	await tap(page, t("loginPassword"));
	await expect(page.getByText(t("mfaTitle"))).toBeVisible();
	// The code of the enrollment can't be used again
	await nextStep(page);
	// The field sends the code at the sixth digit. With its autofill hint (one-time code) Flutter
	// edits it in an input of its own, not in the one of the semantics. The autofocus starts it
	// when the page loads with this screen (not after the login): loaded again
	await page.reload();
	await semantics(page);
	const verified = page.waitForResponse(response => response.url().endsWith("/api/auth/totp"));
	await page.locator("input.flt-text-editing").focus();
	await page.keyboard.type(totp(secret));
	expect((await verified).status()).toBe(200);
	await expect(page.getByRole("button", { name: new RegExp(`^${t("navMap")}`) })).toBeVisible();
});
