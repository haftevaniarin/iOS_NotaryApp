// Regenerate with: node scripts/generate-order-rule-fixtures.mjs /path/to/notary-web-app
// Uses the web implementation itself; fixture data contains no real order details.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const webRoot = process.argv[2];
if (!webRoot) throw new Error('Pass the existing web app repository path.');
const utilsPath = path.join(webRoot, 'src/utils/notary.js');
const appPath = path.join(webRoot, 'src/App.jsx');
const utils = await import(pathToFileURL(utilsPath));
const app = fs.readFileSync(appPath, 'utf8');
const scheduleSource = app.slice(app.indexOf('function getOrderDateTimeTimestamp('), app.indexOf('function buildOrderScheduleWarning('));
const windowMinutes = Number(app.match(/const ORDER_OVERLAP_WARNING_WINDOW_MINUTES = (\d+);/)[1]);
const overlap = new Function('toCalendarDateInputValue', 'toTimeInputValue', 'ORDER_OVERLAP_WARNING_WINDOW_MINUTES', `${scheduleSource}; return getOrderScheduleOverlap;`)(utils.toCalendarDateInputValue, utils.toTimeInputValue, windowMinutes);
const calendarDates = new Set(['2026-08-03', '2026-08-07', '2026-11-25', '2026-07-02', '2021-12-29', '2024-02-28', '2026-03-06', '2026-10-30']);
for (let year = 2024; year <= 2030; year++) {
  for (let month = 1; month <= 12; month++) {
    for (const day of [1, 15, 25, 28]) calendarDates.add(`${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`);
  }
}
process.env.TZ = 'America/Los_Angeles';
const rescission = [...calendarDates].sort().map(date => ({ date, ...utils.calculateRescissionDeadline(date) }));
const order = (id, date, time, paymentStatus = 'Scheduled') => ({id, date, ...(time === undefined ? {} : {time}), paymentStatus, customerName: 'Sample title', signerName: 'Sample signer', fee: 100, paid: paymentStatus === 'Paid'});
const examples = [
  { name: 'inclusive-two-hours', draft: { date: '2026-11-12', time: '14:00' }, orders: [order('boundary', '2026-11-12', '16:00')] },
  { name: 'resolved-one-minute-outside', draft: { date: '2026-11-12', time: '13:59' }, orders: [order('boundary', '2026-11-12', '16:00')] },
  { name: 'nearest-not-first', draft: { date: '2026-11-12', time: '14:00' }, orders: [order('far', '2026-11-12', '16:00'), order('near', '2026-11-12', '14:15')] },
  { name: 'no-time', draft: { date: '2026-11-12', time: '' }, orders: [order('timed', '2026-11-12', '14:00')] },
  { name: 'ignore-edited-order', draft: { date: '2026-11-12', time: '14:00' }, excludedOrderID: 'self', orders: [order('self', '2026-11-12', '14:00')] },
  { name: 'cancelled-is-not-excluded', draft: { date: '2026-11-12', time: '14:00' }, orders: [order('cancelled', '2026-11-12', '14:00', 'Cancelled')] },
  { name: 'paid-is-not-excluded', draft: { date: '2026-11-12', time: '14:00' }, orders: [order('paid', '2026-11-12', '14:00', 'Paid')] },
  { name: 'across-midnight', draft: { date: '2026-11-13', time: '00:30' }, orders: [order('late', '2026-11-12', '23:30')] },
  { name: 'utc-local-day', draft: { date: '2026-11-12', time: '23:30' }, orders: [order('utc', '2026-11-13T07:30:00.000Z')] },
  { name: 'offset-local-day', draft: { date: '2026-11-12', time: '23:30' }, orders: [order('offset', '2026-11-13T02:30:00-05:00')] },
  { name: 'spring-gap', draft: { date: '2026-03-08', time: '02:30' }, orders: [order('gap', '2026-03-08', '03:30')] },
  { name: 'autumn-repeat', draft: { date: '2026-11-01', time: '01:30' }, orders: [order('repeat', '2026-11-01', '02:30')] },
  { name: 'untimed-day', draft: { date: '2026-11-12', time: '00:30' }, orders: [order('day-only', '2026-11-12')] },
  { name: 'explicit-midnight', draft: { date: '2026-11-12', time: '00:30' }, orders: [order('midnight', '2026-11-12', '00:00')] }
];
const scheduling = [];
for (const timeZone of ['America/Los_Angeles', 'America/New_York', 'UTC', 'Pacific/Kiritimati']) {
  process.env.TZ = timeZone;
  for (const test of examples) {
    const result = overlap(test.draft, test.orders.map(utils.normalizeOrderForUi), test.excludedOrderID);
    scheduling.push({ ...test, timeZone, expectedOrderID: result?.order?.id ?? null });
  }
}
const sha = value => createHash('sha256').update(value).digest('hex');
const fixture = { provenance: { webFiles: ['src/App.jsx', 'src/utils/notary.js'], appSHA256: sha(app), utilsSHA256: sha(fs.readFileSync(utilsPath)), windowMinutes }, rescission, scheduling };
const output = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../notaryledger-iosTests/order-rule-web-parity.json');
fs.writeFileSync(output, JSON.stringify(fixture, null, 2) + '\n');
console.log(`Generated ${rescission.length} rescission and ${scheduling.length} scheduling fixtures from the web implementation.`);
