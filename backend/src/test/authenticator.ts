import crypto from "node:crypto";

// Software authenticator for the tests: creates and uses a real ES256 passkey (attestation
// "none", user verified), so the WebAuthn verification runs end to end.

type Cbor = number | string | Buffer | Cbor[] | Map<Cbor, Cbor> | { [key: string]: Cbor };

function head (major: number, value: number): Buffer {
	if (value < 24) return Buffer.from([(major << 5) | value]);
	if (value < 256) return Buffer.from([(major << 5) | 24, value]);
	if (value < 65536) return Buffer.from([(major << 5) | 25, value >> 8, value & 0xff]);
	const buffer = Buffer.alloc(5);
	buffer[0] = (major << 5) | 26;
	buffer.writeUInt32BE(value, 1);
	return buffer;
}

export function cbor (value: Cbor): Buffer {
	if (typeof value === "number") return value >= 0 ? head(0, value) : head(1, -1 - value);
	if (typeof value === "string") {
		const bytes = Buffer.from(value, "utf8");
		return Buffer.concat([head(3, bytes.length), bytes]);
	}
	if (Buffer.isBuffer(value)) return Buffer.concat([head(2, value.length), value]);
	if (Array.isArray(value)) return Buffer.concat([head(4, value.length), ...value.map(cbor)]);
	const entries = value instanceof Map ? [...value.entries()] : Object.entries(value);
	return Buffer.concat([head(5, entries.length), ...entries.flatMap(([key, item]) => [cbor(key), cbor(item)])]);
}

const b64 = (data: Buffer | string) => Buffer.from(data).toString("base64url");
const sha256 = (data: Buffer | string) => crypto.createHash("sha256").update(data).digest();

const FLAG_UP = 0x01;
const FLAG_UV = 0x04;
const FLAG_AT = 0x40;

export class SoftAuthenticator {
	readonly credentialId = crypto.randomBytes(16);
	readonly #keys = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
	readonly origin: string;
	readonly rpId: string;
	#counter = 0;
	#userHandle = "";

	constructor (origin: string, rpId: string) {
		this.origin = origin;
		this.rpId = rpId;
	}

	get id (): string {
		return b64(this.credentialId);
	}

	#clientData (type: string, challenge: string, origin = this.origin): Buffer {
		return Buffer.from(JSON.stringify({ type, challenge, origin, crossOrigin: false }));
	}

	#authData (flags: number, extra: Buffer = Buffer.alloc(0), rpId = this.rpId): Buffer {
		const counter = Buffer.alloc(4);
		counter.writeUInt32BE(this.#counter);
		return Buffer.concat([sha256(rpId), Buffer.from([flags]), counter, extra]);
	}

	/** Answer to the registration options of the server */
	register (options: { challenge: string; user: { id: string } }, tamper: { origin?: string; flags?: number } = {}) {
		this.#userHandle = options.user.id;
		const jwk = this.#keys.publicKey.export({ format: "jwk" });
		const cose = cbor(new Map<Cbor, Cbor>([[1, 2], [3, -7], [-1, 1], [-2, Buffer.from(jwk.x!, "base64url")], [-3, Buffer.from(jwk.y!, "base64url")]]));
		const idLength = Buffer.alloc(2);
		idLength.writeUInt16BE(this.credentialId.length);
		const attested = Buffer.concat([Buffer.alloc(16), idLength, this.credentialId, cose]);
		const authData = this.#authData(tamper.flags ?? (FLAG_UP | FLAG_UV | FLAG_AT), attested);
		return {
			id: this.id,
			rawId: this.id,
			type: "public-key",
			response: {
				clientDataJSON: b64(this.#clientData("webauthn.create", options.challenge, tamper.origin)),
				attestationObject: b64(cbor({ fmt: "none", attStmt: {}, authData })),
				transports: ["internal"]
			},
			clientExtensionResults: {},
			authenticatorAttachment: "platform"
		};
	}

	/** Answer to the authentication options of the server */
	authenticate (options: { challenge: string }, tamper: { origin?: string; flags?: number; badSignature?: boolean } = {}) {
		this.#counter++;
		const clientData = this.#clientData("webauthn.get", options.challenge, tamper.origin);
		const authData = this.#authData(tamper.flags ?? (FLAG_UP | FLAG_UV));
		let signature = crypto.sign("sha256", Buffer.concat([authData, sha256(clientData)]), this.#keys.privateKey);
		if (tamper.badSignature) signature = crypto.sign("sha256", Buffer.from("other"), this.#keys.privateKey);
		return {
			id: this.id,
			rawId: this.id,
			type: "public-key",
			response: {
				clientDataJSON: b64(clientData),
				authenticatorData: b64(authData),
				signature: b64(signature),
				userHandle: this.#userHandle
			},
			clientExtensionResults: {},
			authenticatorAttachment: "platform"
		};
	}
}
