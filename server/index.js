const express = require("express");
const { initAPNS } = require("./apns");
const { startPoller } = require("./mta");

const app = express();
app.use(express.json());

// In-memory registration store: token -> feed info
const registrations = new Map();

app.post("/register", (req, res) => {
  const { token, feedId, line, directionStopId, stationName, direction } =
    req.body;

  if (!token || !line || !directionStopId) {
    return res.status(400).json({ error: "Missing required fields" });
  }

  registrations.set(token, {
    feedId,
    line,
    directionStopId,
    stationName,
    direction,
  });
  console.log(
    `Registered: ${token.substring(0, 8)}... for ${line} at ${stationName} (${registrations.size} total)`
  );
  res.json({ ok: true });
});

app.delete("/register/:token", (req, res) => {
  const deleted = registrations.delete(req.params.token);
  console.log(
    `Unregistered: ${req.params.token.substring(0, 8)}... (${deleted ? "found" : "not found"}, ${registrations.size} remaining)`
  );
  res.json({ ok: true });
});

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    registrations: registrations.size,
  });
});

const PORT = process.env.PORT || 3000;

async function main() {
  initAPNS();
  await startPoller(registrations);
  app.listen(PORT, () => console.log(`Server listening on port ${PORT}`));
}

main().catch(console.error);
