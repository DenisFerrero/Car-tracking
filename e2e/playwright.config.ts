import { defineConfig, devices } from "@playwright/test";

// Run by run.sh: BASE_URL is the backend with the web app, INVITE_URL the invite of the
// first administrator. One worker: the tests share the account and follow each other.
export default defineConfig({
	testDir: "tests",
	fullyParallel: false,
	workers: 1,
	retries: 0,
	timeout: 120_000,
	expect: { timeout: 15_000 },
	outputDir: "results",
	reporter: [["list"], ["html", { outputFolder: "report", open: "never" }]],
	use: {
		...devices["Desktop Chrome"],
		baseURL: process.env.BASE_URL,
		actionTimeout: 15_000,
		locale: "it-IT",
		timezoneId: "Europe/Rome",
		screenshot: "only-on-failure",
		trace: "retain-on-failure"
	}
});
