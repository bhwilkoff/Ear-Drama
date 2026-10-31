/**
 * Export (Human-Shaped principle 11): the JSON holds history, follows, queue, and takes; the CSV
 * quotes what needs it. Runs the SHIPPED js/store.js and js/export.js.
 *
 *   node js/export.test.js
 */
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert');

const mem = new Map();
Object.defineProperty(globalThis, 'localStorage', {
  value: { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => { mem.set(k, String(v)); },
           removeItem: (k) => { mem.delete(k); }, clear: () => mem.clear() },
  configurable: true, writable: true,
});
vm.runInThisContext(fs.readFileSync(`${__dirname}/store.js`, 'utf-8'), { filename: 'store.js' });
const DataExport = require('./export.js');

const ep = (id, title) => ({ id, title, series: id.split('|')[0], seriesName: 'The "Quoted", Show', date: '1949-02-03' });
Store.addHistory(ep('a|1', 'One, with a comma'));
Store.savePosition('a|1', 600, 1800);
Store.addHistory(ep('a|2', 'Two'));
Store.enqueue(ep('a|3', 'Three'));
Store.toggleFollow({ key: 'a', name: 'A Show' });
const productions = [{ id: 'p1', title: 'Play', created: 1000, chosen: { l1: 't1' },
  takes: [{ id: 't1', lineID: 'l1' }, { id: 't2', lineID: 'l1' }] }];

const data = DataExport.build(Store, productions, Date.parse('2026-10-30T12:00:00Z'));
assert.strictEqual(data.exportedAt, '2026-10-30T12:00:00.000Z');
assert.deepStrictEqual(data.history.map(h => h.episode), ['a|2', 'a|1'], 'history, newest first');
assert.strictEqual(data.history[1].positionSeconds, 600, 'the resume point travels with the row');
assert.deepStrictEqual(data.following, [{ series: 'a', name: 'A Show' }]);
assert.deepStrictEqual(data.queue.map(q => [q.position, q.episode]), [[1, 'a|3']]);
assert.deepStrictEqual(data.takes[0].takes.map(t => [t.id, t.chosen]), [['t1', true], ['t2', false]]);

const csv = DataExport.historyCsv(data).split('\r\n');
assert.strictEqual(csv[0], 'episode,title,seriesName,airDate,listenedAt,positionSeconds,durationSeconds');
assert.ok(csv[2].includes('"One, with a comma"'), 'a comma is quoted');
assert.ok(csv[2].includes('"The ""Quoted"", Show"'), 'a quote is doubled');
assert.strictEqual(csv.length, 4, 'header, two rows, trailing newline');

const empty = DataExport.build({ history: () => [], follows: () => [], queue: () => [], position: () => null }, []);
assert.deepStrictEqual([empty.history, empty.following, empty.queue, empty.takes], [[], [], [], []]);
assert.strictEqual(DataExport.historyCsv(empty), 'episode,title,seriesName,airDate,listenedAt,positionSeconds,durationSeconds\r\n');
console.log('export: all passed');
