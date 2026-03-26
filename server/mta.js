const protobuf = require("protobufjs");
const AdmZip = require("adm-zip");
const path = require("path");
const { randomUUID } = require("crypto");
const { sendPushBatch } = require("./apns");

// Swift encodes Date as seconds since Jan 1, 2001 (reference date).
const SWIFT_REFERENCE_DATE_OFFSET = 978307200;

const FEED_URLS = {
  1: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  2: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  3: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  4: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  5: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  6: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  A: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
  C: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
  E: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
  B: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
  D: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
  F: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
  M: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
  G: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g",
  J: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
  Z: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
  L: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l",
  N: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
  Q: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
  R: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
  W: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
  7: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-7",
  S: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
};

let FeedMessage;
let stopNameMap = {};

async function init() {
  const root = await protobuf.load(
    path.join(__dirname, "../Proto/gtfs-realtime.proto")
  );
  FeedMessage = root.lookupType("transit_realtime.FeedMessage");

  await loadStopNames();
}

async function loadStopNames() {
  console.log("Downloading GTFS static data...");
  const response = await fetch(
    "http://web.mta.info/developers/data/nyct/subway/google_transit.zip"
  );
  const buffer = Buffer.from(await response.arrayBuffer());
  const zip = new AdmZip(buffer);
  const stopsEntry = zip.getEntry("stops.txt");
  if (!stopsEntry) {
    console.warn("stops.txt not found in GTFS zip");
    return;
  }

  const csv = stopsEntry.getData().toString("utf8");
  const lines = csv.split("\n");
  const headers = lines[0].split(",").map((h) => h.trim());
  const idIdx = headers.indexOf("stop_id");
  const nameIdx = headers.indexOf("stop_name");

  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(",");
    if (!cols[idIdx] || !cols[nameIdx]) continue;
    const stopId = cols[idIdx].trim();
    const name = cols[nameIdx].trim();
    stopNameMap[stopId] = name;
    // Also index without directional suffix
    if (stopId.endsWith("N") || stopId.endsWith("S")) {
      const prefix = stopId.slice(0, -1);
      if (!stopNameMap[prefix]) stopNameMap[prefix] = name;
    }
  }
  console.log(`Loaded ${Object.keys(stopNameMap).length} stop names`);
}

function lastStopName(tripUpdate, line) {
  const stops = tripUpdate.stopTimeUpdate;
  if (!stops || stops.length === 0) return line;
  const stopId = stops[stops.length - 1].stopId;
  if (!stopId) return line;

  if (stopNameMap[stopId]) return stopNameMap[stopId];
  if (stopId.endsWith("N") || stopId.endsWith("S")) {
    const prefix = stopId.slice(0, -1);
    if (stopNameMap[prefix]) return stopNameMap[prefix];
  }
  return line;
}

function toSwiftDate(unixTimestamp) {
  return unixTimestamp - SWIFT_REFERENCE_DATE_OFFSET;
}

/**
 * Poll MTA feeds for all registered activities and push updates.
 * @param {Map} registrations - Map<token, {feedId, line, directionStopId, ...}>
 */
async function pollAndPush(registrations) {
  if (registrations.size === 0) return;

  // Group registrations by MTA feed URL to batch HTTP requests
  const byUrl = new Map();
  for (const [token, reg] of registrations) {
    const url = FEED_URLS[reg.line];
    if (!url) continue;
    if (!byUrl.has(url)) byUrl.set(url, []);
    byUrl.get(url).push({ token, ...reg });
  }

  const allPushes = [];

  for (const [url, regs] of byUrl) {
    try {
      const response = await fetch(url);
      const buffer = Buffer.from(await response.arrayBuffer());
      const raw = FeedMessage.decode(new Uint8Array(buffer));
      const message = FeedMessage.toObject(raw, { longs: Number });
      const now = Date.now() / 1000;

      for (const { token, line, directionStopId } of regs) {
        const departures = [];

        for (const entity of message.entity || []) {
          if (!entity.tripUpdate) continue;
          const trip = entity.tripUpdate;
          if (!trip.trip || !trip.trip.routeId) continue;
          if (!trip.trip.routeId.startsWith(line)) continue;

          for (const stopTime of trip.stopTimeUpdate || []) {
            if (stopTime.stopId !== directionStopId) continue;

            let arrivalTime;
            if (stopTime.arrival && stopTime.arrival.time) {
              arrivalTime = Number(stopTime.arrival.time);
            } else if (stopTime.departure && stopTime.departure.time) {
              arrivalTime = Number(stopTime.departure.time);
            } else {
              continue;
            }

            if (arrivalTime - now < 0) continue;

            departures.push({
              id: randomUUID().toUpperCase(),
              line,
              destination: lastStopName(trip, line),
              arrivalTime: toSwiftDate(arrivalTime),
            });
          }
        }

        departures.sort((a, b) => a.arrivalTime - b.arrivalTime);

        allPushes.push({
          token,
          contentState: {
            departures: departures.slice(0, 6),
            updatedAt: toSwiftDate(now),
          },
        });
      }
    } catch (err) {
      console.error(`MTA fetch error for ${url}:`, err.message);
    }
  }

  if (allPushes.length > 0) {
    await sendPushBatch(allPushes);
    console.log(`Pushed updates to ${allPushes.length} activities`);
  }
}

async function startPoller(registrations) {
  await init();

  // Initial poll
  await pollAndPush(registrations);

  // Then every 30 seconds
  setInterval(() => pollAndPush(registrations), 30_000);
  console.log("MTA poller started (30s interval)");
}

module.exports = { startPoller };
