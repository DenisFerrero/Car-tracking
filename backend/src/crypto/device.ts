import crypto from "node:crypto";

// Secrets of the trackers, all derived from CRYPTO_MASTER_KEY and the IMEI: nothing to
// store, and a secret extracted from a tracker compromises only that tracker.

// Truncated Poly1305 tag: 8 bytes keep the forgery probability at 2^-64 saving SIM data
export const TAG_LENGTH = 8;
const NONCE_LENGTH = 12;

// Nonce direction, keeps device and server nonces in separate domains
export const DIRECTION_UPLINK = 0;
export const DIRECTION_DOWNLINK = 1;

const DEVICE_KEY_CONTEXT = "car-tracking/device-key/v2:";
const PAIRING_CONTEXT = "car-tracking/pairing/v2:";

// Crockford base32, without ambiguous characters (I, L, O, U)
const BASE32_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export const IMEI_PATTERN = /^\d{15}$/;

export class DeviceSecrets {
	readonly #masterKey: Buffer;

	constructor (masterKey: string) {
		if (masterKey.length < 32) throw new Error("CRYPTO_MASTER_KEY too short (min 32 characters)");
		this.#masterKey = Buffer.from(masterKey, "utf8");
	}

	#hmac (context: string, imei: string): Buffer {
		return crypto.createHmac("sha256", this.#masterKey).update(context + imei).digest();
	}

	/** 32 bytes ChaCha20-Poly1305 key of a tracker */
	deviceKey (imei: string): Buffer {
		return this.#hmac(DEVICE_KEY_CONTEXT, imei);
	}

	/**
	 * Code printed on the tracker label: with the IMEI it proves the physical possession
	 * of the tracker when an owner adds it to the account. Format XXXX-XXXX (40 bits).
	 */
	pairingCode (imei: string): string {
		const digest = this.#hmac(PAIRING_CONTEXT, imei);
		let bits = 0n;
		for (const byte of digest.subarray(0, 5)) bits = (bits << 8n) | BigInt(byte);

		let code = "";
		for (let i = 7; i >= 0; i--) code += BASE32_ALPHABET[Number((bits >> BigInt(i * 5)) & 31n)];
		return code.slice(0, 4) + "-" + code.slice(4);
	}

	verifyPairingCode (imei: string, code: string): boolean {
		const expected = Buffer.from(normalizePairingCode(this.pairingCode(imei)));
		const provided = Buffer.from(normalizePairingCode(code));
		return expected.length === provided.length && crypto.timingSafeEqual(expected, provided);
	}
}

export function normalizePairingCode (code: string): string {
	return code.toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1").replace(/[^0-9A-Z]/g, "");
}

export function buildNonce (counter: number, timestamp: number, direction: number): Buffer {
	const nonce = Buffer.alloc(NONCE_LENGTH);
	nonce.writeUInt32LE(counter >>> 0, 0);
	nonce.writeUInt32LE(timestamp >>> 0, 4);
	nonce.writeUInt32LE(direction >>> 0, 8);
	return nonce;
}

export function seal (key: Buffer, nonce: Buffer, aad: Buffer, plaintext: Buffer): { ciphertext: Buffer; tag: Buffer } {
	const cipher = crypto.createCipheriv("chacha20-poly1305", key, nonce, { authTagLength: TAG_LENGTH });
	cipher.setAAD(aad, { plaintextLength: plaintext.length });
	const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
	return { ciphertext, tag: cipher.getAuthTag() };
}

/** Decrypts and authenticates, null when the tag doesn't match */
export function open (key: Buffer, nonce: Buffer, aad: Buffer, ciphertext: Buffer, tag: Buffer): Buffer | null {
	try {
		const decipher = crypto.createDecipheriv("chacha20-poly1305", key, nonce, { authTagLength: TAG_LENGTH });
		decipher.setAAD(aad, { plaintextLength: ciphertext.length });
		decipher.setAuthTag(tag);
		return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
	} catch {
		return null;
	}
}
