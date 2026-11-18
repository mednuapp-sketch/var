"use strict";
// In-memory fake of the Firestore Admin API subset used by the MedNu money code.
// Enforces the real read-before-write rule inside transactions.

class Timestamp {
  constructor(ms) { this._ms = ms; }
  static now() { return new Timestamp(Date.now()); }
  static fromMillis(ms) { return new Timestamp(ms); }
  static fromDate(d) { return new Timestamp(d.getTime()); }
  toMillis() { return this._ms; }
  toDate() { return new Date(this._ms); }
  get seconds() { return Math.floor(this._ms / 1000); }
}

class Sentinel { constructor(kind, arg) { this.kind = kind; this.arg = arg; } }
const FieldValue = {
  serverTimestamp: () => new Sentinel("ts"),
  increment: (n) => new Sentinel("inc", n),
  delete: () => new Sentinel("del"),
  arrayUnion: (...v) => new Sentinel("union", v),
  arrayRemove: (...v) => new Sentinel("remove", v),
};

const clone = (v) => {
  if (v instanceof Timestamp || v instanceof Sentinel) return v;
  if (Array.isArray(v)) return v.map(clone);
  if (v && typeof v === "object") { const o = {}; for (const k of Object.keys(v)) o[k] = clone(v[k]); return o; }
  return v;
};
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function resolveValue(existing, v) {
  if (!(v instanceof Sentinel)) return clone(v);
  switch (v.kind) {
    case "ts": return Timestamp.now();
    case "inc": return (typeof existing === "number" ? existing : 0) + v.arg;
    case "union": { const base = Array.isArray(existing) ? existing.slice() : []; for (const x of v.arg) if (!base.some((y) => eq(x, y))) base.push(x); return base; }
    case "remove": return (Array.isArray(existing) ? existing : []).filter((y) => !v.arg.some((x) => eq(x, y)));
    default: return undefined;
  }
}

function applyMerge(target, src) {
  for (const k of Object.keys(src)) {
    const v = src[k];
    if (v instanceof Sentinel && v.kind === "del") { delete target[k]; continue; }
    if (v && typeof v === "object" && !(v instanceof Sentinel) && !(v instanceof Timestamp) && !Array.isArray(v)) {
      if (!target[k] || typeof target[k] !== "object" || target[k] instanceof Timestamp) target[k] = {};
      applyMerge(target[k], v);
    } else target[k] = resolveValue(target[k], v);
  }
}
function setPath(obj, path, v) {
  const parts = path.split(".");
  let cur = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!cur[parts[i]] || typeof cur[parts[i]] !== "object") cur[parts[i]] = {};
    cur = cur[parts[i]];
  }
  const last = parts[parts.length - 1];
  if (v instanceof Sentinel && v.kind === "del") delete cur[last];
  else cur[last] = resolveValue(cur[last], v);
}
function getPath(obj, path) {
  let cur = obj;
  for (const p of path.split(".")) { if (cur == null || typeof cur !== "object") return undefined; cur = cur[p]; }
  return cur;
}
const hasSentinel = (o) => o instanceof Sentinel || (o && typeof o === "object" && !(o instanceof Timestamp) &&
  (Array.isArray(o) ? o.some(hasSentinel) : Object.values(o).some(hasSentinel)));

class DocSnap {
  constructor(ref, data) { this.ref = ref; this.id = ref.id; this._d = data; }
  get exists() { return this._d !== undefined; }
  data() { return this._d === undefined ? undefined : clone(this._d); }
  get(path) { return this._d === undefined ? undefined : clone(getPath(this._d, path)); }
}
class QuerySnap {
  constructor(docs) { this.docs = docs; this.size = docs.length; this.empty = docs.length === 0; }
  forEach(fn) { this.docs.forEach(fn); }
}

class DocRef {
  constructor(store, path) { this._s = store; this.path = path; this.id = path.split("/").pop(); }
  get parent() { return new CollRef(this._s, this.path.split("/").slice(0, -1).join("/")); }
  collection(name) { return new CollRef(this._s, `${this.path}/${name}`); }
  async get() { return new DocSnap(this, this._s.read(this.path)); }
  async set(data, opts) { this._s.commit([{ op: "set", ref: this, data, merge: !!(opts && opts.merge) }]); }
  async update(data) { this._s.commit([{ op: "update", ref: this, data }]); }
  async create(data) { this._s.commit([{ op: "create", ref: this, data }]); }
  async delete() { this._s.commit([{ op: "delete", ref: this }]); }
}

class Query {
  constructor(store, coll, filters = [], order = null, lim = null) { this._s = store; this._c = coll; this._f = filters; this._o = order; this._l = lim; }
  where(field, op, value) { return new Query(this._s, this._c, [...this._f, { field, op, value }], this._o, this._l); }
  orderBy(field, dir = "asc") { return new Query(this._s, this._c, this._f, { field, dir }, this._l); }
  limit(n) { return new Query(this._s, this._c, this._f, this._o, n); }
  _norm(v) { return v instanceof Timestamp ? v.toMillis() : v; }
  _run() {
    let docs = this._s.listCollection(this._c).map(([path, d]) => new DocSnap(new DocRef(this._s, path), d));
    for (const f of this._f) {
      docs = docs.filter((s) => {
        const a = this._norm(s.get(f.field)); const b = this._norm(f.value);
        switch (f.op) {
          case "==": return eq(a, b);
          case "!=": return !eq(a, b);
          case ">": return a > b; case ">=": return a >= b;
          case "<": return a < b; case "<=": return a <= b;
          case "in": return Array.isArray(f.value) && f.value.some((x) => eq(a, this._norm(x)));
          case "array-contains": return Array.isArray(a) && a.some((x) => eq(x, b));
          default: throw new Error(`fake: unsupported op ${f.op}`);
        }
      });
    }
    if (this._o) {
      const { field, dir } = this._o;
      docs.sort((x, y) => { const a = this._norm(x.get(field)), b = this._norm(y.get(field)); return (a > b ? 1 : a < b ? -1 : 0) * (dir === "desc" ? -1 : 1); });
    }
    if (this._l != null) docs = docs.slice(0, this._l);
    return new QuerySnap(docs);
  }
  async get() { return this._run(); }
}

class CollRef extends Query {
  constructor(store, path) { super(store, path); this.path = path; this.id = path.split("/").pop(); }
  doc(id) { return new DocRef(this._s, `${this.path}/${id || this._s.autoId()}`); }
  async add(data) { const r = this.doc(); await r.create(data); return r; }
}

class Store {
  constructor() { this.docs = new Map(); this._n = 0; }
  autoId() { return `auto${String(++this._n).padStart(6, "0")}`; }
  read(path) { return this.docs.get(path); }
  listCollection(coll) {
    const depth = coll.split("/").length + 1;
    return [...this.docs.entries()].filter(([p]) => p.startsWith(coll + "/") && p.split("/").length === depth);
  }
  // Applies all ops atomically; throws without side effects on failure.
  commit(ops) {
    const staged = new Map();
    const get = (p) => (staged.has(p) ? staged.get(p) : this.docs.get(p));
    for (const o of ops) {
      const p = o.ref.path;
      const cur = get(p);
      if (o.op === "create") {
        if (cur !== undefined) { const e = new Error(`6 ALREADY_EXISTS: ${p}`); e.code = 6; throw e; }
        const d = {}; applyMerge(d, o.data); staged.set(p, d);
      } else if (o.op === "set") {
        if (o.merge && cur !== undefined) { const d = clone(cur); applyMerge(d, o.data); staged.set(p, d); }
        else { const d = {}; applyMerge(d, o.data); staged.set(p, d); }
      } else if (o.op === "update") {
        if (cur === undefined) { const e = new Error(`5 NOT_FOUND: ${p}`); e.code = 5; throw e; }
        const d = clone(cur);
        for (const k of Object.keys(o.data)) setPath(d, k, o.data[k]);
        staged.set(p, d);
      } else if (o.op === "delete") staged.set(p, undefined);
    }
    for (const [p, d] of staged) { if (d === undefined) this.docs.delete(p); else this.docs.set(p, d); }
  }
}

class Transaction {
  constructor(store) { this._s = store; this._ops = []; }
  async get(refOrQuery) {
    if (this._ops.length) throw new Error("Firestore transactions require all reads to be executed before all writes.");
    return refOrQuery.get();
  }
  set(ref, data, opts) { this._ops.push({ op: "set", ref, data, merge: !!(opts && opts.merge) }); return this; }
  update(ref, data) { this._ops.push({ op: "update", ref, data }); return this; }
  create(ref, data) { this._ops.push({ op: "create", ref, data }); return this; }
  delete(ref) { this._ops.push({ op: "delete", ref }); return this; }
}

class FakeDb {
  constructor() { this.store = new Store(); }
  collection(name) { return new CollRef(this.store, name); }
  doc(path) { return new DocRef(this.store, path); }
  async getAll(...refs) { return Promise.all(refs.map((r) => r.get())); }
  batch() {
    const ops = [];
    const b = {
      set: (ref, data, opts) => { ops.push({ op: "set", ref, data, merge: !!(opts && opts.merge) }); return b; },
      update: (ref, data) => { ops.push({ op: "update", ref, data }); return b; },
      create: (ref, data) => { ops.push({ op: "create", ref, data }); return b; },
      delete: (ref) => { ops.push({ op: "delete", ref }); return b; },
      commit: async () => this.store.commit(ops),
    };
    return b;
  }
  async runTransaction(fn) {
    const tx = new Transaction(this.store);
    const result = await fn(tx);
    this.store.commit(tx._ops);
    return result;
  }
  // Test helpers
  seed(path, data) { const d = {}; applyMerge(d, data); this.store.docs.set(path, d); }
  peek(path) { const d = this.store.docs.get(path); return d === undefined ? undefined : clone(d); }
  list(coll) { return this.store.listCollection(coll).map(([p, d]) => ({ id: p.split("/").pop(), ...clone(d) })); }
}

module.exports = { FakeDb, FieldValue, Timestamp };
