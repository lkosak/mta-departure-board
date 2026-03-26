const http2 = require("http2");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const BUNDLE_ID = "io.lou.subwayboard";
const TOPIC = `${BUNDLE_ID}.push-type.liveactivity`;

let teamId, keyId, signingKey;
let cachedToken = null;
let tokenExpiry = 0;

function initAPNS() {
  teamId = process.env.APNS_TEAM_ID;
  keyId = process.env.APNS_KEY_ID;
  const keyPath = process.env.APNS_KEY_PATH;

  if (!teamId || !keyId || !keyPath) {
    console.warn(
      "APNs not configured - set APNS_TEAM_ID, APNS_KEY_ID, APNS_KEY_PATH"
    );
    return false;
  }

  signingKey = fs.readFileSync(path.resolve(keyPath), "utf8");
  console.log("APNs configured");
  return true;
}

function getToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now < tokenExpiry) return cachedToken;

  const header = Buffer.from(
    JSON.stringify({ alg: "ES256", kid: keyId })
  ).toString("base64url");
  const claims = Buffer.from(
    JSON.stringify({ iss: teamId, iat: now })
  ).toString("base64url");

  const signature = crypto
    .createSign("SHA256")
    .update(`${header}.${claims}`)
    .sign(signingKey, "base64url");

  cachedToken = `${header}.${claims}.${signature}`;
  tokenExpiry = now + 3500; // Refresh before 1hr expiry
  return cachedToken;
}

/**
 * Send a batch of push updates over a single HTTP/2 connection.
 * @param {Array<{token: string, contentState: object}>} pushes
 */
async function sendPushBatch(pushes) {
  if (!signingKey || pushes.length === 0) return;

  const host = process.env.APNS_HOST || "api.push.apple.com";
  const client = http2.connect(`https://${host}`);

  client.on("error", (err) => {
    console.error("APNs connection error:", err.message);
  });

  const results = await Promise.allSettled(
    pushes.map(
      ({ token, contentState }) =>
        new Promise((resolve) => {
          const now = Math.floor(Date.now() / 1000);
          const payload = JSON.stringify({
            aps: {
              timestamp: now,
              event: "update",
              "content-state": contentState,
              "stale-date": now + 60,
              "dismissal-date": now + 86400,
            },
          });

          const req = client.request({
            ":method": "POST",
            ":path": `/3/device/${token}`,
            authorization: `bearer ${getToken()}`,
            "apns-topic": TOPIC,
            "apns-push-type": "liveactivity",
            "apns-priority": "10",
            "content-type": "application/json",
            "content-length": Buffer.byteLength(payload),
          });

          let data = "";
          req.on("response", (headers) => {
            const status = headers[":status"];
            req.on("data", (chunk) => (data += chunk));
            req.on("end", () => {
              if (status !== 200) {
                console.error(
                  `APNs ${status} for ${token.substring(0, 8)}...: ${data}`
                );
              }
              resolve({ token, status, data });
            });
          });

          req.on("error", (err) => {
            console.error(
              `APNs request error for ${token.substring(0, 8)}...:`,
              err.message
            );
            resolve({ token, status: 0, error: err.message });
          });

          req.end(payload);
        })
    )
  );

  client.close();
  return results;
}

module.exports = { initAPNS, sendPushBatch };
