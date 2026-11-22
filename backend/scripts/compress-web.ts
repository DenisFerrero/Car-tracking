import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

// Writes .br and .gz next to the text files of the web build (main.dart.js is ~4 MB, ~1 MB
// with brotli): @fastify/static serves them to the browsers that accept them.
//   node scripts/compress-web.ts <web root>

const EXTENSIONS = new Set([".js", ".mjs", ".json", ".html", ".css", ".wasm", ".svg", ".otf", ".ttf", ".txt"]);
const MIN_SIZE = 1024;

export function compressTree (root: string): number {
	let count = 0;
	for (const entry of fs.readdirSync(root, { withFileTypes: true, recursive: true })) {
		if (!entry.isFile() || !EXTENSIONS.has(path.extname(entry.name))) continue;
		const file = path.join(entry.parentPath, entry.name);
		const data = fs.readFileSync(file);
		if (data.length < MIN_SIZE) continue;
		fs.writeFileSync(`${file}.br`, zlib.brotliCompressSync(data, {
			params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: data.length }
		}));
		fs.writeFileSync(`${file}.gz`, zlib.gzipSync(data, { level: 9 }));
		count++;
	}
	return count;
}

if (import.meta.main) {
	const root = process.argv[2];
	if (!root) {
		console.error("Usage: node scripts/compress-web.ts <web root>");
		process.exit(1);
	}
	console.log(`Compressed ${compressTree(path.resolve(root))} files`);
}
