import { loadConfig } from "./config.ts";
import { startServer } from "./server.ts";

try {
	const server = await startServer(loadConfig());

	const shutdown = async (signal: string) => {
		server.ctx.log.info(`${signal} received, shutting down`);
		await server.close();
		process.exit(0);
	};
	process.once("SIGTERM", () => void shutdown("SIGTERM"));
	process.once("SIGINT", () => void shutdown("SIGINT"));
} catch (error) {
	console.error(error);
	process.exit(1);
}
