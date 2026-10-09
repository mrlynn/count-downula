// Host Passes are bought with StoreKit 2, which signs every transaction as a JWS. The server checks
// that signature itself: the certificate chain in the header has to end at Apple's root, the
// certificates have to carry Apple's App Store markers, and the payload has to be our product.
// That needs no App Store Server API key.
import { X509Certificate, verify } from "node:crypto";

/** SHA-256 of Apple Root CA - G3 (apple.com/certificateauthority), which signs App Store transactions. */
export const APPLE_ROOT_G3_SHA256 =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

export const BUNDLE_ID = "com.countdownula.app";
export const HOST_PASS_PRODUCT_ID = "com.countdownula.app.hostpass";

// Apple's marker extensions: the leaf (1.2.840.113635.100.6.11.1) and the intermediate
// (1.2.840.113635.100.6.2.1), as DER-encoded object identifiers.
const LEAF_OID = Buffer.from("060a2a864886f76364060b01", "hex");
const INTERMEDIATE_OID = Buffer.from("060a2a864886f76364060201", "hex");

export interface SignedTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  type: string;
  purchaseDate: number;
  signedDate: number;
  environment: string;
  revocationDate?: number;
}

export type Verified = { ok: true; value: SignedTransaction } | { ok: false; error: string };

const fail = (error: string): Verified => ({ ok: false, error });

function part(segment: string): Record<string, unknown> | null {
  try {
    return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function validAt(cert: X509Certificate, at: Date): boolean {
  return new Date(cert.validFrom) <= at && at <= new Date(cert.validTo);
}

/**
 * Verifies a StoreKit 2 transaction JWS and returns its payload. `allowXcode` accepts transactions
 * from Xcode's local StoreKit testing, which are signed by Xcode rather than Apple; never in production.
 */
export function verifyTransaction(
  jws: string,
  options: { rootFingerprint?: string; allowXcode?: boolean; productId?: string; bundleId?: string } = {},
): Verified {
  const segments = typeof jws === "string" ? jws.split(".") : [];
  if (segments.length !== 3) return fail("That isn't a signed transaction.");
  const header = part(segments[0]);
  const payload = part(segments[1]) as Partial<SignedTransaction> | null;
  if (!header || !payload) return fail("That isn't a signed transaction.");
  if (header.alg !== "ES256") return fail("Unexpected signature algorithm.");
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length === 0 || !x5c.every((c) => typeof c === "string")) return fail("Missing certificates.");

  let certs: X509Certificate[];
  try {
    certs = (x5c as string[]).map((c) => new X509Certificate(Buffer.from(c, "base64")));
  } catch {
    return fail("Unreadable certificates.");
  }
  const leaf = certs[0];
  const signature = Buffer.from(segments[2], "base64url");
  const signedOK = verify("sha256", Buffer.from(`${segments[0]}.${segments[1]}`), { key: leaf.publicKey, dsaEncoding: "ieee-p1363" }, signature);
  if (!signedOK) return fail("The signature doesn't match.");

  const xcode = options.allowXcode === true && payload.environment === "Xcode";
  if (!xcode) {
    if (certs.length !== 3) return fail("Unexpected certificate chain.");
    const [, intermediate, root] = certs;
    // Certificates are judged at the moment Apple signed the transaction, so an expired leaf
    // doesn't invalidate an old purchase.
    const at = new Date(typeof payload.signedDate === "number" ? payload.signedDate : Date.now());
    if (root.fingerprint256 !== (options.rootFingerprint ?? APPLE_ROOT_G3_SHA256)) return fail("Not signed by Apple.");
    if (!root.verify(root.publicKey) || !intermediate.verify(root.publicKey) || !leaf.verify(intermediate.publicKey)) {
      return fail("The certificate chain doesn't hold.");
    }
    if (!certs.every((c) => validAt(c, at))) return fail("A certificate wasn't valid when this was signed.");
    if (!leaf.raw.includes(LEAF_OID) || !intermediate.raw.includes(INTERMEDIATE_OID)) return fail("Not an App Store certificate.");
    if (payload.environment !== "Production" && payload.environment !== "Sandbox") return fail("Unknown App Store environment.");
  }

  if (payload.bundleId !== (options.bundleId ?? BUNDLE_ID)) return fail("That purchase is for another app.");
  if (payload.productId !== (options.productId ?? HOST_PASS_PRODUCT_ID)) return fail("That purchase isn't a Host Pass.");
  if (payload.type !== "Consumable") return fail("Unexpected purchase type.");
  if (payload.revocationDate) return fail("That purchase was refunded.");
  if (typeof payload.transactionId !== "string" || typeof payload.originalTransactionId !== "string") return fail("Missing transaction ID.");
  return { ok: true, value: payload as SignedTransaction };
}
