// ============================================
//   MEDNU ADMIN — PANEL v2
//   Profile dashboard, read-only partner account
//   directory, profile-change requests, minor
//   requests, order / ambulance tracking, patient
//   health data and scoped (Finance / Quality) reports.
//
//   Loaded after app.js — relies on its globals
//   (db, auth, escHtml, switchTab, canAccessTab, ...).
// ============================================

// ---- small shared helpers ----
function _pick(obj, ...keys) {
  for (const k of keys) {
    const v = obj && obj[k];
    if (v !== undefined && v !== null && v !== '') return v;
  }
  return '';
}
function _tsMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.toDate === 'function') return v.toDate().getTime();
  const t = new Date(v).getTime();
  return isNaN(t) ? 0 : t;
}
function _fmtWhen(v) {
  const ms = _tsMillis(v);
  if (!ms) return '—';
  return new Date(ms).toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}
function _fmtDay(v) {
  const ms = _tsMillis(v);
  return ms ? new Date(ms).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
}
function _money(v) {
  const n = Number(v);
  return isNaN(n) || v === '' || v == null ? '—' : '₹' + n.toLocaleString('en-IN');
}
function _emptyRow(cols, msg) {
  return `<tr><td colspan="${cols}"><div class="empty-state"><div class="empty-icon"><i class="ti ti-inbox"></i></div><p>${escHtml(msg)}</p></div></td></tr>`;
}
function _statTile(num, label, color) {
  return `<div class="card stat-tile"><div class="stat-num" style="color:${color || 'var(--primary)'};">${escHtml(String(num))}</div><div class="stat-lbl">${escHtml(label)}</div></div>`;
}
function copyToClipboard(text, btn) {
  const done = () => {
    showToast('Copied to clipboard');
    if (btn) { btn.classList.add('copied'); setTimeout(() => btn.classList.remove('copied'), 1200); }
  };
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, () => showToast('Copy failed'));
  else showToast('Copy not supported in this browser');
}

// ---- tab dispatcher (called from switchTab in app.js) ----
function onPanelTabOpened(tab) {
  if (tab === 'home') renderHome();
  if (tab.startsWith('acct-')) openAccountsView(tab);
  if (tab === 'care-assistant-partners') setCaregiverKind('care_assistant');
  else if (tab === 'caregiver-partners') setCaregiverKind('nurse');
  if (tab === 'spec-requests') renderProfileChangeRequests();
  if (tab === 'minor-requests') initMinorRequests();
  if (tab === 'order-tracking') initOrderTracking();
  if (tab === 'ambulance-tracking') initAmbulanceTracking();
}

// Called once from app.js after the admin's role is known.
function onPanelReady() {
  // Keep the Minor Requests badge live for profiles that can open it.
  if (canAccessTab('minor-requests')) initMinorRequests();
  initProfileChangeWatch();
}

// ============================================
//   NURSES / CARE ASSISTANTS (shared partner table)
// ============================================
function setCaregiverKind(kind) {
  _caregiverKind = kind;
  const t = document.getElementById('cp-title');
  if (t) t.textContent = kind === 'care_assistant' ? 'All Care Assistants' : 'All Nurses';
  const search = document.getElementById('cp-search');
  if (search) search.placeholder = kind === 'care_assistant' ? 'Search care assistant name…' : 'Search nurse name / specialty…';
  if (typeof filterPartnerTable === 'function') filterPartnerTable('caregiver');
}

// ============================================
//   MY DASHBOARD (profile-specific home)
// ============================================
let _homeTimer = null;

function _navItemLabel(item) {
  const c = item.cloneNode(true);
  c.querySelectorAll('.nav-badge, i').forEach(n => n.remove());
  return c.textContent.replace(/\s+/g, ' ').trim();
}

function _visibleNavSections() {
  const sections = [];
  document.querySelectorAll('.nav-section-label[data-section]').forEach(label => {
    if (label.style.display === 'none') return;
    const items = [];
    let sib = label.nextElementSibling;
    while (sib && !sib.classList.contains('nav-section-label')) {
      if (sib.classList.contains('nav-item') && sib.style.display !== 'none' && sib.dataset.tab) {
        const badge = sib.querySelector('.nav-badge-red');
        const n = badge && badge.style.display !== 'none' ? parseInt(badge.textContent, 10) || 0 : 0;
        items.push({
          tab: sib.dataset.tab,
          title: sib.dataset.title,
          label: _navItemLabel(sib),
          icon: (sib.querySelector('.nav-icon') || {}).className || 'ti ti-circle',
          attention: n,
          el: sib,
        });
      }
      sib = sib.nextElementSibling;
    }
    const txt = label.querySelector('.nav-section-text');
    sections.push({
      name: txt ? txt.textContent.trim() : label.textContent.trim(),
      icon: (label.querySelector('.nav-section-text i') || {}).className || 'ti ti-folder',
      items,
    });
  });
  return sections;
}

function renderHome() {
  const root = document.getElementById('home-sections');
  if (!root) return;
  const meta = ROLE_LABELS[currentAdminRole] || { name: capitalize(currentAdminRole), tag: '', icon: 'ti-user' };
  const user = auth.currentUser;
  const first = ((user && (user.displayName || (user.email || '').split('@')[0])) || meta.name).split(/[.\s_-]/)[0];
  const hr = new Date().getHours();
  const greet = hr < 12 ? 'Good morning' : hr < 17 ? 'Good afternoon' : 'Good evening';
  const setT = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  setT('home-eyebrow', greet + ', ' + capitalize(first));
  setT('home-title', meta.name + ' workspace');
  setT('home-sub', meta.tag);
  const chip = document.getElementById('home-role-chip');
  if (chip) chip.innerHTML = `<i class="ti ${escHtml(meta.icon)}"></i> <span>${escHtml(meta.name)} profile</span>`;

  const sections = _visibleNavSections()
    .map(s => ({ ...s, items: s.items.filter(i => i.tab !== 'home') }))
    .filter(s => s.items.length);

  const attention = [];
  sections.forEach(s => s.items.forEach(i => { if (i.attention > 0) attention.push({ ...i, section: s.name }); }));
  const attEl = document.getElementById('home-attention');
  if (attEl) {
    if (attention.length) {
      attEl.style.display = '';
      attEl.innerHTML = `<div class="home-att-title"><i class="ti ti-bell-ringing"></i> Needs your attention</div>
        <div class="home-att-list">${attention.map(a =>
          `<button class="home-att-item" onclick="switchTab(${escJsAttr(a.tab)},${escJsAttr(a.title || '')})">
             <span class="home-att-count">${a.attention}</span>
             <span class="home-att-label">${escHtml(a.label)}<small>${escHtml(a.section)}</small></span>
             <i class="ti ti-chevron-right"></i>
           </button>`).join('')}</div>`;
    } else {
      attEl.style.display = 'none';
      attEl.innerHTML = '';
    }
  }

  root.innerHTML = sections.map(s => `
    <div class="card home-card">
      <div class="home-card-head"><span class="home-card-ico"><i class="${escHtml(s.icon)}"></i></span>
        <span class="home-card-title">${escHtml(s.name)}</span><span class="home-card-n">${s.items.length}</span></div>
      <div class="home-links">${s.items.map(i => `
        <button class="home-link" onclick="switchTab(${escJsAttr(i.tab)},${escJsAttr(i.title || '')})">
          <i class="${escHtml(i.icon)}"></i><span>${escHtml(i.label)}</span>${i.attention ? `<b>${i.attention}</b>` : ''}
        </button>`).join('')}</div>
    </div>`).join('');

  // Badges update live in the sidebar — keep the cards in step while visible.
  clearInterval(_homeTimer);
  _homeTimer = setInterval(() => {
    const tab = document.getElementById('tab-home');
    if (!tab || !tab.classList.contains('active')) { clearInterval(_homeTimer); return; }
    renderHome();
  }, 6000);
}

// ============================================
//   PARTNER ACCOUNTS (read-only directory)
// ============================================
const ACCT_VIEWS = {
  'acct-doctors':         { title: 'Doctor Accounts',         noun: 'doctors',         source: 'doctors' },
  'acct-nurses':          { title: 'Nurse Accounts',          noun: 'nurses',          source: 'partner', role: 'caregiver', kind: 'nurse' },
  'acct-care-assistants': { title: 'Care Assistant Accounts', noun: 'care assistants', source: 'partner', role: 'caregiver', kind: 'care_assistant' },
  'acct-lab':             { title: 'Lab & Diagnostics Accounts', noun: 'labs',         source: 'partner', role: 'lab' },
  'acct-pharmacy':        { title: 'Pharmacy Accounts',       noun: 'pharmacies',      source: 'partner', role: 'pharmacy' },
  'acct-ambulance':       { title: 'Ambulance Accounts',      noun: 'ambulance partners', source: 'partner', role: 'ambulance' },
  'acct-physio':          { title: 'Physiotherapy Accounts',  noun: 'physiotherapists', source: 'partner', role: 'physiotherapy' },
  'acct-dietician':       { title: 'Dietician Accounts',      noun: 'dieticians',      source: 'partner', role: 'nutrition' },
  'acct-hospitals':       { title: 'Hospital Accounts',       noun: 'hospitals',       source: 'partner', role: 'hospital' },
  'acct-equipment':       { title: 'Equipment Accounts',      noun: 'equipment vendors', source: 'partner', role: 'equipment' },
  'acct-counsellors':     { title: 'Counsellor Accounts',     noun: 'counsellors',     source: 'partner', role: 'counselling' },
};
let _acctTab = null;

function openAccountsView(tab) {
  _acctTab = tab;
  const view = ACCT_VIEWS[tab];
  if (!view) return;
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
  set('acct-search', '');
  set('acct-status-filter', 'all');
  const t = document.getElementById('acct-title');
  if (t) t.textContent = view.title;
  renderAccountsView();
}

function _acctStatus(raw) {
  const s = String(raw || 'pending').toLowerCase();
  if (['active', 'approved', 'verified'].includes(s)) return 'active';
  if (['suspended', 'deactivated', 'inactive', 'rejected', 'blocked', 'disabled'].includes(s)) return 'deactivated';
  return 'pending';
}

function _acctRows(view) {
  if (view.source === 'doctors') {
    return (allDoctors || []).map(d => ({
      id: d.id,
      name: d.name || 'Unnamed doctor',
      sub: d.specialty || d.specialisation || d.specialization || d.email || '',
      phone: d.phone || '',
      location: _pick(d, 'city', 'hospital', 'location'),
      ratingHtml: (d.totalReviews > 0 && d.rating > 0) ? `★ ${escHtml(Number(d.rating).toFixed(1))} <span class="acct-muted">(${escHtml(String(d.totalReviews))})</span>` : '<span class="acct-muted">—</span>',
      joined: d.createdAt,
      status: _acctStatus(d.status),
      flagged: d.flagged === true || d.isFlagged === true,
    }));
  }
  const cfg = PARTNER_ROLES[view.role];
  let list = _partnerData[view.role] || [];
  if (view.kind) list = list.filter(p => (p.serviceType === 'care_assistant') === (view.kind === 'care_assistant'));
  return list.map(p => ({
    id: p.id,
    name: cfg.nameOf(p),
    sub: cfg.subOf ? cfg.subOf(p) : '',
    phone: _pick(p, 'phone', 'driverPhone', 'contactPhone', 'mobile'),
    location: _pick(p, 'city', 'area', 'location', 'address'),
    ratingHtml: (p.totalReviews > 0 && p.rating > 0) ? partnerRatingCell(p) : '<span class="acct-muted">—</span>',
    joined: p.createdAt,
    status: _acctStatus(partnerStatusOf(p)),
    flagged: p.flagged === true || p.isFlagged === true,
  }));
}

function renderAccountsView() {
  const view = ACCT_VIEWS[_acctTab];
  const tbody = document.getElementById('acct-tbody');
  if (!view || !tbody) return;
  const rows = _acctRows(view);
  const q = (document.getElementById('acct-search')?.value || '').trim().toLowerCase();
  const sf = document.getElementById('acct-status-filter')?.value || 'all';

  const count = (fn) => rows.filter(fn).length;
  document.getElementById('acct-stats').innerHTML =
    _statTile(rows.length, 'Total accounts', 'var(--primary)') +
    _statTile(count(r => r.status === 'active'), 'Active', '#1e8e3e') +
    _statTile(count(r => r.flagged), 'Flagged', '#e65100') +
    _statTile(count(r => r.status === 'deactivated'), 'Deactivated', '#c62828');
  const sub = document.getElementById('acct-sub');
  if (sub) sub.innerHTML = `<i class="ti ti-list-details"></i> ${rows.length} ${escHtml(view.noun)} · pending ${count(r => r.status === 'pending')}`;

  let list = rows;
  if (sf === 'flagged') list = list.filter(r => r.flagged);
  else if (sf !== 'all') list = list.filter(r => r.status === sf);
  if (q) list = list.filter(r => [r.name, r.id, r.phone, r.location, r.sub].join(' ').toLowerCase().includes(q));
  list = [...list].sort((a, b) => _tsMillis(b.joined) - _tsMillis(a.joined));

  if (!list.length) { tbody.innerHTML = _emptyRow(7, rows.length ? 'No accounts match these filters.' : 'No accounts yet.'); return; }
  const key = 'acct-' + _acctTab;
  tbody.innerHTML = list.slice(0, pageShown(key)).map(r => {
    const color = randomAvatarColor(r.name);
    const label = r.status === 'deactivated' ? 'Deactivated' : capitalize(r.status);
    return `<tr>
      <td><div class="user-cell"><div class="doc-avatar" style="background:${escHtml(color.bg)};color:${escHtml(color.fg)};">${escHtml(getInitials(r.name))}</div>
        <div><div class="user-name">${escHtml(r.name)}</div><div class="user-sub">${escHtml(r.sub || '')}</div></div></div></td>
      <td><span class="id-chip" title="${escHtml(r.id)}"><code>${escHtml(r.id)}</code>
        <button class="id-copy" onclick="copyToClipboard('${escHtml(r.id)}', this)" aria-label="Copy account ID"><i class="ti ti-copy"></i></button></span></td>
      <td>${escHtml(r.phone || '—')}</td>
      <td>${escHtml(String(r.location || '—'))}</td>
      <td>${r.ratingHtml}</td>
      <td class="acct-muted">${escHtml(_fmtDay(r.joined))}</td>
      <td><span class="pill pill-${r.status === 'deactivated' ? 'suspended' : escHtml(r.status)}">${escHtml(label)}</span>${r.flagged ? ' <span class="pill pill-flagged"><i class="ti ti-flag-filled"></i> Flagged</span>' : ''}</td>
    </tr>`;
  }).join('') + loadMoreRow(key, list.length, 7, 'renderAccountsView();');
}

// Keep the directory live: the existing partner/doctor listeners already
// refresh their own tables, so piggy-back on those instead of a second query.
(function wrapLiveRefresh() {
  const refreshIfOpen = () => {
    const tab = document.getElementById('tab-accounts');
    if (tab && tab.classList.contains('active')) renderAccountsView();
    const req = document.getElementById('tab-spec-requests');
    if (req && req.classList.contains('active')) renderProfileChangeRequests();
    updateRequestsBadge();
  };
  ['renderCombinedPendingList', 'filterDoctorsTable'].forEach(fn => {
    const orig = window[fn];
    if (typeof orig !== 'function') return;
    window[fn] = function () { const r = orig.apply(this, arguments); refreshIfOpen(); return r; };
  });
})();

// ============================================
//   REQUESTS — profile change requests (Main)
// ============================================
let _pcrCount = 0;

function _pendingProfileEdits() {
  const out = [];
  (allDoctors || []).forEach(d => {
    if (d.hasPendingChanges) out.push({ kind: 'doctor', typeLabel: 'Doctor', id: d.id, name: d.name || 'Doctor', changes: d.pendingChanges || {} });
  });
  Object.keys(PARTNER_ROLES).forEach(role => {
    (_partnerData[role] || []).forEach(p => {
      if (p.hasPendingChanges) {
        const label = role === 'caregiver' && p.serviceType === 'care_assistant' ? 'Care Assistant' : PARTNER_ROLES[role].label.replace(/ Partner$/, '');
        out.push({ kind: role, typeLabel: label, id: p.id, name: PARTNER_ROLES[role].nameOf(p), changes: p.pendingChanges || {} });
      }
    });
  });
  return out;
}

function _humanKey(k) {
  return String(k).replace(/([a-z])([A-Z])/g, '$1 $2').replace(/[_.]/g, ' ').replace(/^./, c => c.toUpperCase());
}

function renderProfileChangeRequests() {
  const rows = _pendingProfileEdits();
  _pcrCount = rows.length;
  const pill = document.getElementById('pcr-count-pill');
  if (pill) pill.textContent = rows.length + ' waiting';
  const tbody = document.getElementById('pcr-tbody');
  if (tbody) {
    tbody.innerHTML = rows.length ? rows.map(r => {
      const keys = Object.keys(r.changes || {});
      const chips = keys.slice(0, 4).map(k => `<span class="svc-type-badge" style="background:#f3e5f5;color:#6a1b9a;">${escHtml(_humanKey(k))}</span>`).join(' ')
        + (keys.length > 4 ? ` <span class="acct-muted">+${keys.length - 4} more</span>` : '');
      const open = r.kind === 'doctor' ? `viewDoctor('${escHtml(r.id)}')` : `showPartnerModal('${escHtml(r.kind)}','${escHtml(r.id)}')`;
      return `<tr>
        <td><div class="user-name">${escHtml(r.name)}</div></td>
        <td><span class="svc-type-badge" style="background:#e3f2fd;color:#1565c0;">${escHtml(r.typeLabel)}</span></td>
        <td><span class="id-chip"><code>${escHtml(r.id)}</code><button class="id-copy" onclick="copyToClipboard('${escHtml(r.id)}', this)" aria-label="Copy ID"><i class="ti ti-copy"></i></button></span></td>
        <td>${chips || '<span class="acct-muted">—</span>'}</td>
        <td><button class="btn btn-approve" onclick="${open}">Review changes</button></td>
      </tr>`;
    }).join('') : _emptyRow(5, 'No profile changes are waiting for approval.');
  }
  updateRequestsBadge();
}

// The Requests nav badge = pending specialization requests + profile edits.
function updateRequestsBadge() {
  const badge = document.getElementById('nav-spec-requests-count');
  if (!badge) return;
  const specs = parseInt((document.getElementById('sr-count-pending') || {}).textContent, 10) || 0;
  const n = specs + _pendingProfileEdits().length;
  badge.textContent = n;
  badge.style.display = n > 0 ? 'inline-flex' : 'none';
}
function initProfileChangeWatch() {
  updateRequestsBadge();
  setInterval(updateRequestsBadge, 5000);
}

// ============================================
//   MINOR REQUESTS (profile photo + phone number)
// ============================================
// Collection: minor_requests — one doc per request:
//   { userId, userType, userName, type: 'photo'|'phone', field, collection,
//     oldValue, newValue, status: 'pending'|'approved'|'rejected', createdAt }
// Approve applies newValue to {collection}/{userId}.{field}. Both the target
// collection and field are whitelisted here because the request doc is
// client-written and must never choose an arbitrary write target.
const MINOR_ALLOWED_COLLECTIONS = ['users', 'doctors'];
const MINOR_ALLOWED_FIELDS = { photo: ['photoUrl', 'photoURL', 'profileImageUrl'], phone: ['phone'] };

let _minorListener = null;
let _minorRows = [];

function initMinorRequests() {
  if (_minorListener) { renderMinorRequests(); return; }
  _minorListener = db.collection('minor_requests').orderBy('createdAt', 'desc').limit(300).onSnapshot(snap => {
    _minorRows = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderMinorRequests();
  }, err => {
    console.error('[minor_requests]', err);
    const tb = document.getElementById('mr-tbody');
    if (tb) tb.innerHTML = _emptyRow(7, 'Could not load requests — check your permissions.');
  });
}

function renderMinorRequests() {
  const rows = _minorRows;
  const cnt = s => rows.filter(r => (r.status || 'pending') === s).length;
  const setT = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  setT('mr-count-pending', cnt('pending'));
  setT('mr-count-approved', cnt('approved'));
  setT('mr-count-rejected', cnt('rejected'));
  setT('mr-count-total', rows.length);
  const badge = document.getElementById('nav-minor-requests-count');
  if (badge) { badge.textContent = cnt('pending'); badge.style.display = cnt('pending') > 0 ? 'inline-flex' : 'none'; }

  const tbody = document.getElementById('mr-tbody');
  if (!tbody) return;
  const tf = document.getElementById('mr-type-filter')?.value || 'all';
  const sf = document.getElementById('mr-status-filter')?.value || 'pending';
  let list = rows;
  if (tf !== 'all') list = list.filter(r => r.type === tf);
  if (sf !== 'all') list = list.filter(r => (r.status || 'pending') === sf);
  if (!list.length) { tbody.innerHTML = _emptyRow(7, 'No profile photo or phone number requests here.'); return; }
  tbody.innerHTML = list.map(r => {
    const st = r.status || 'pending';
    const isPhoto = r.type === 'photo';
    const val = (v) => isPhoto
      ? (v ? `<a href="${escHtml(v)}" target="_blank" rel="noopener noreferrer"><img class="mr-thumb" src="${escHtml(v)}" alt="" loading="lazy" referrerpolicy="no-referrer"/></a>` : '<span class="acct-muted">None</span>')
      : escHtml(v || '—');
    return `<tr>
      <td><div class="user-name">${escHtml(r.userName || '—')}</div><div class="user-sub">${escHtml(capitalize(r.userType || ''))} · <code>${escHtml(String(r.userId || '').slice(0, 10))}…</code></div></td>
      <td><span class="svc-type-badge" style="background:${isPhoto ? '#e8eaf6' : '#e0f2f1'};color:${isPhoto ? '#3949ab' : '#00695c'};"><i class="ti ${isPhoto ? 'ti-photo' : 'ti-phone'}"></i> ${isPhoto ? 'Profile photo' : 'Phone number'}</span></td>
      <td>${val(r.oldValue)}</td>
      <td>${val(r.newValue)}</td>
      <td class="acct-muted">${escHtml(_fmtWhen(r.createdAt))}</td>
      <td><span class="pill pill-${st === 'approved' ? 'active' : st === 'rejected' ? 'suspended' : 'pending'}">${escHtml(capitalize(st))}</span></td>
      <td>${st === 'pending' ? `<button class="btn btn-approve" onclick="decideMinorRequest('${escHtml(r.id)}','approved', this)">Approve</button>
        <button class="btn btn-reject" style="margin-left:4px;" onclick="decideMinorRequest('${escHtml(r.id)}','rejected', this)">Reject</button>` : '<span class="acct-muted">—</span>'}</td>
    </tr>`;
  }).join('');
}

async function decideMinorRequest(id, decision, btn) {
  const r = _minorRows.find(x => x.id === id);
  if (!r) return;
  if (btn) btn.disabled = true;
  try {
    const meta = { status: decision, reviewedAt: firebase.firestore.FieldValue.serverTimestamp(), reviewedBy: auth.currentUser?.email || 'admin' };
    if (decision === 'approved') {
      const okColl  = MINOR_ALLOWED_COLLECTIONS.includes(r.collection || 'users');
      const okField = (MINOR_ALLOWED_FIELDS[r.type] || []).includes(r.field);
      if (!r.userId || !okColl || !okField || !r.newValue) throw new Error('This request has an unsupported target — reject it instead.');
      const batch = db.batch();
      batch.update(db.collection(r.collection || 'users').doc(r.userId), { [r.field]: r.newValue, updatedAt: firebase.firestore.FieldValue.serverTimestamp() });
      batch.update(db.collection('minor_requests').doc(id), meta);
      await batch.commit();
    } else {
      await db.collection('minor_requests').doc(id).update(meta);
    }
    showToast(decision === 'approved' ? 'Change approved and applied ✓' : 'Request rejected');
  } catch (err) {
    console.error('decideMinorRequest', err);
    showToast(err.message || 'Could not update the request');
    if (btn) btn.disabled = false;
  }
}

// ============================================
//   TRACKING OF ORDERS
// ============================================
const _orderStore = { pharmacy: [], equipment: [], diagnostics: [] };
let _orderListeners = null;

const ORDER_SOURCES = [
  { key: 'pharmacy',    coll: 'pharmacy_orders',     label: 'Pharmacy',    vendor: o => _pick(o, 'pharmacyName', 'vendorName', 'storeName') },
  { key: 'equipment',   coll: 'equipment_orders',    label: 'Equipment',   vendor: o => _pick(o, 'vendorName', 'equipmentVendorName', 'storeName') },
  { key: 'diagnostics', coll: 'diagnostic_bookings', label: 'Diagnostics', vendor: o => _pick(o, 'labName', 'vendorName') },
];

function _statusGroup(status) {
  const s = String(status || '').toLowerCase();
  if (['delivered', 'completed', 'complete', 'report_ready', 'reported', 'done', 'collected'].includes(s)) return 'done';
  if (['cancelled', 'canceled', 'rejected', 'failed', 'refunded', 'declined'].includes(s)) return 'cancelled';
  return 'open';
}
function _statusPill(status) {
  const g = _statusGroup(status);
  const cls = g === 'done' ? 'completed' : g === 'cancelled' ? 'rejected' : 'pending';
  return `<span class="pill pill-${cls}">${escHtml(capitalize(String(status || 'placed').replace(/_/g, ' ')))}</span>`;
}

function initOrderTracking() {
  if (_orderListeners) { renderOrderTracking(); return; }
  _orderListeners = ORDER_SOURCES.map(src =>
    db.collection(src.coll).orderBy('createdAt', 'desc').limit(150).onSnapshot(snap => {
      _orderStore[src.key] = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      renderOrderTracking();
    }, err => {
      console.error('[' + src.coll + ']', err);
      _orderStore[src.key] = [];
      renderOrderTracking();
    }));
}

function renderOrderTracking() {
  const tbody = document.getElementById('ot-tbody');
  if (!tbody) return;
  const all = [];
  ORDER_SOURCES.forEach(src => _orderStore[src.key].forEach(o => all.push({ o, src })));
  const g = fn => all.filter(x => fn(x)).length;
  document.getElementById('ot-stats').innerHTML =
    _statTile(all.length, 'Orders tracked', 'var(--primary)') +
    _statTile(g(x => _statusGroup(x.o.status) === 'open'), 'In progress', '#f57f17') +
    _statTile(g(x => _statusGroup(x.o.status) === 'done'), 'Delivered / completed', '#1e8e3e') +
    _statTile(g(x => _statusGroup(x.o.status) === 'cancelled'), 'Cancelled', '#c62828');

  const q  = (document.getElementById('ot-search')?.value || '').trim().toLowerCase();
  const tf = document.getElementById('ot-type-filter')?.value || 'all';
  const sf = document.getElementById('ot-status-filter')?.value || 'all';
  let list = all;
  if (tf !== 'all') list = list.filter(x => x.src.key === tf);
  if (sf !== 'all') list = list.filter(x => _statusGroup(x.o.status) === sf);
  if (q) list = list.filter(x => [x.o.id, _pick(x.o, 'patientName', 'patientId'), x.src.vendor(x.o)].join(' ').toLowerCase().includes(q));
  list = [...list].sort((a, b) => _tsMillis(b.o.createdAt) - _tsMillis(a.o.createdAt));
  if (!list.length) { tbody.innerHTML = _emptyRow(7, all.length ? 'No orders match these filters.' : 'No orders yet.'); return; }
  tbody.innerHTML = list.slice(0, pageShown('orders')).map(({ o, src }) => `<tr>
    <td><span class="id-chip"><code>${escHtml(o.id.slice(0, 10))}</code><button class="id-copy" onclick="copyToClipboard('${escHtml(o.id)}', this)" aria-label="Copy order ID"><i class="ti ti-copy"></i></button></span></td>
    <td><span class="svc-type-badge" style="background:#f3e5f5;color:#6a1b9a;">${escHtml(src.label)}</span></td>
    <td>${escHtml(_pick(o, 'patientName', 'customerName') || String(o.patientId || '—').slice(0, 10))}</td>
    <td>${escHtml(src.vendor(o) || 'Awaiting vendor')}</td>
    <td>${_money(_pick(o, 'totalAmount', 'total', 'amount', 'finalAmount', 'price'))}</td>
    <td class="acct-muted">${escHtml(_fmtWhen(o.createdAt))}</td>
    <td>${_statusPill(o.status)}</td>
  </tr>`).join('') + loadMoreRow('orders', list.length, 7, 'renderOrderTracking();');
}

// ============================================
//   AMBULANCE TRACKING
// ============================================
let _ambTrackListener = null;
let _ambTrackRows = [];

function _ambGroup(status) {
  const s = String(status || '').toLowerCase();
  if (['completed', 'dropped', 'delivered', 'done'].includes(s)) return 'done';
  if (['cancelled', 'canceled', 'rejected', 'expired'].includes(s)) return 'cancelled';
  if (['pending', 'requested', 'searching', 'unassigned', ''].includes(s)) return 'pending';
  return 'active';
}

function initAmbulanceTracking() {
  if (_ambTrackListener) { renderAmbulanceTracking(); return; }
  _ambTrackListener = db.collection('ambulance_requests').orderBy('createdAt', 'desc').limit(200).onSnapshot(snap => {
    _ambTrackRows = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderAmbulanceTracking();
  }, err => {
    console.error('[ambulance_requests]', err);
    const tb = document.getElementById('at-tbody');
    if (tb) tb.innerHTML = _emptyRow(7, 'Could not load ambulance requests — check your permissions.');
  });
}

function renderAmbulanceTracking() {
  const tbody = document.getElementById('at-tbody');
  if (!tbody) return;
  const rows = _ambTrackRows;
  const c = k => rows.filter(r => _ambGroup(r.status) === k).length;
  document.getElementById('at-stats').innerHTML =
    _statTile(c('active'), 'On the way / in progress', '#1565c0') +
    _statTile(c('pending'), 'Waiting for a driver', '#f57f17') +
    _statTile(c('done'), 'Completed', '#1e8e3e') +
    _statTile(c('cancelled'), 'Cancelled', '#c62828');
  const q  = (document.getElementById('at-search')?.value || '').trim().toLowerCase();
  const sf = document.getElementById('at-status-filter')?.value || 'all';
  let list = rows;
  if (sf !== 'all') list = list.filter(r => _ambGroup(r.status) === sf);
  if (q) list = list.filter(r => [r.id, _pick(r, 'patientName', 'patientId'), _pick(r, 'driverName', 'ambulanceName'), _pick(r, 'pickupAddress', 'pickup')].join(' ').toLowerCase().includes(q));
  if (!list.length) { tbody.innerHTML = _emptyRow(7, rows.length ? 'No requests match these filters.' : 'No ambulance requests yet.'); return; }
  const addr = v => (v && typeof v === 'object') ? _pick(v, 'address', 'name', 'label') : v;
  tbody.innerHTML = list.slice(0, pageShown('ambtrack')).map(r => {
    const g = _ambGroup(r.status);
    const cls = g === 'done' ? 'completed' : g === 'cancelled' ? 'rejected' : g === 'active' ? 'accepted' : 'pending';
    return `<tr>
      <td><span class="id-chip"><code>${escHtml(r.id.slice(0, 10))}</code><button class="id-copy" onclick="copyToClipboard('${escHtml(r.id)}', this)" aria-label="Copy request ID"><i class="ti ti-copy"></i></button></span></td>
      <td>${escHtml(_pick(r, 'patientName', 'customerName') || String(r.patientId || '—').slice(0, 10))}</td>
      <td>${escHtml(_pick(r, 'driverName', 'ambulanceName', 'ambulancePlate') || 'Not assigned')}</td>
      <td>${escHtml(String(addr(_pick(r, 'pickupAddress', 'pickup', 'pickupLocation')) || '—'))}</td>
      <td>${escHtml(String(addr(_pick(r, 'destinationAddress', 'destination', 'dropAddress', 'hospitalName')) || '—'))}</td>
      <td class="acct-muted">${escHtml(_fmtWhen(r.createdAt))}</td>
      <td><span class="pill pill-${cls}">${escHtml(capitalize(String(r.status || 'pending').replace(/_/g, ' ')))}</span></td>
    </tr>`;
  }).join('') + loadMoreRow('ambtrack', list.length, 7, 'renderAmbulanceTracking();');
}

// ============================================
//   HEALTH DATA (of a patient ID)
// ============================================
function _hdField(label, value) {
  const empty = value === undefined || value === null || value === '';
  return `<div class="hd-field"><div class="hd-label">${escHtml(label)}</div><div class="hd-value${empty ? ' empty' : ''}">${empty ? 'Not provided' : escHtml(Array.isArray(value) ? value.join(', ') : String(value))}</div></div>`;
}

async function lookupHealthData(ev) {
  if (ev) ev.preventDefault();
  if (!canAccessTab('health-data')) return;
  const out = document.getElementById('hd-result');
  const id = (document.getElementById('hd-patient-id')?.value || '').trim();
  if (!id || id.includes('/')) { showToast('Enter a valid patient ID'); return; }
  const btn = document.getElementById('hd-search-btn');
  if (btn) btn.disabled = true;
  out.innerHTML = '<div class="loading">Looking up patient…</div>';
  try {
    const userSnap = await db.collection('users').doc(id).get();
    if (!userSnap.exists) {
      out.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-user-search"></i></div><p>No patient found with that ID.</p></div>';
      return;
    }
    const u = userSnap.data();
    const safe = async (p) => { try { return await p; } catch (e) { return null; } };
    const [recSnap, bmiSnap, rxSnap] = await Promise.all([
      safe(db.collection('health_records').doc(id).collection('records').limit(30).get()),
      safe(db.collection('bmi_logs').where('userId', '==', id).limit(20).get()),
      safe(db.collection('prescriptions').where('patientId', '==', id).limit(20).get()),
    ]);
    // The lookup itself is sensitive access — leave an audit trail.
    try {
      await db.collection('operation_logs').add({
        userId: auth.currentUser.uid, userType: 'admin', action: 'admin_view_health_data', status: 'success',
        details: { patientId: id, role: currentAdminRole },
        timestamp: firebase.firestore.FieldValue.serverTimestamp(),
        expiresAt: firebase.firestore.Timestamp.fromMillis(Date.now() + 90 * 86400000),
      });
    } catch (e) { /* logging must never block the lookup */ }

    const name = u.name || 'Patient';
    const color = randomAvatarColor(name);
    const records = recSnap ? recSnap.docs.map(d => ({ id: d.id, ...d.data() })) : [];
    const bmis = bmiSnap ? bmiSnap.docs.map(d => d.data()).sort((a, b) => _tsMillis(b.createdAt || b.date) - _tsMillis(a.createdAt || a.date)) : [];
    const rxs = rxSnap ? rxSnap.docs.map(d => ({ id: d.id, ...d.data() })) : [];

    out.innerHTML = `
      <div class="card hd-head">
        <div class="doc-avatar hd-avatar" style="background:${escHtml(color.bg)};color:${escHtml(color.fg)};">${escHtml(getInitials(name))}</div>
        <div class="hd-head-text"><div class="hd-name">${escHtml(name)}</div>
          <div class="user-sub">ID <code>${escHtml(id)}</code> · ${escHtml(u.gender || '—')}${u.dob ? ' · ' + escHtml(String(typeof calcAge === 'function' ? calcAge(u.dob) : '')) + ' yrs' : ''}</div></div>
      </div>
      <div class="hd-grid">
        <div class="card"><div class="card-header"><span class="card-title">Vitals &amp; Profile</span></div>
          <div class="hd-fields">
            ${_hdField('Blood group', u.bloodGroup)}${_hdField('Height', u.height ? u.height + ' cm' : '')}${_hdField('Weight', u.weight ? u.weight + ' kg' : '')}
            ${_hdField('Allergies', u.allergies)}${_hdField('Chronic conditions', u.chronicConditions)}${_hdField('Current medications', _pick(u, 'currentMedications', 'medications'))}
          </div></div>
        <div class="card"><div class="card-header"><span class="card-title">BMI Log</span></div>
          ${bmis.length ? `<div class="hd-list">${bmis.slice(0, 8).map(b => `<div class="hd-row"><span>${escHtml(_fmtDay(b.createdAt || b.date))}</span><b>${escHtml(String(_pick(b, 'bmi', 'value') || '—'))}</b><span class="acct-muted">${escHtml(_pick(b, 'weight') ? b.weight + ' kg' : '')}</span></div>`).join('')}</div>` : '<div class="empty-state"><p>No BMI entries.</p></div>'}
        </div>
        <div class="card"><div class="card-header"><span class="card-title">Health Records</span><span class="pill pill-pending">${records.length}</span></div>
          ${records.length ? `<div class="hd-list">${records.map(r => `<div class="hd-row"><span>${escHtml(String(_pick(r, 'title', 'name', 'type') || 'Record'))}</span><span class="acct-muted">${escHtml(_fmtDay(_pick(r, 'createdAt', 'date', 'uploadedAt')))}</span>${_pick(r, 'fileUrl', 'url', 'imageUrl') ? `<a class="btn btn-outline" target="_blank" rel="noopener noreferrer" href="${escHtml(_pick(r, 'fileUrl', 'url', 'imageUrl'))}">Open</a>` : ''}</div>`).join('')}</div>` : '<div class="empty-state"><p>No uploaded records.</p></div>'}
        </div>
        <div class="card"><div class="card-header"><span class="card-title">Prescriptions</span><span class="pill pill-pending">${rxs.length}</span></div>
          ${rxs.length ? `<div class="hd-list">${rxs.map(r => `<div class="hd-row"><span>${escHtml(String(_pick(r, 'rxId', 'prescriptionId') || r.id.slice(0, 8)))}</span><span class="acct-muted">${escHtml(_pick(r, 'doctorName') || '')}</span><span class="acct-muted">${escHtml(_fmtDay(r.createdAt))}</span></div>`).join('')}</div>` : '<div class="empty-state"><p>No prescriptions.</p></div>'}
        </div>
      </div>`;
  } catch (err) {
    console.error('lookupHealthData', err);
    out.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-alert-circle"></i></div><p>Could not load health data — check your permissions.</p></div>';
  } finally {
    if (btn) btn.disabled = false;
  }
}

// ============================================
//   SCOPED REPORTS (Finance + Quality Assessment)
// ============================================
const REPORT_SOURCES = {
  payments:                { label: 'Revenue & Payments',        date: 'createdAt', scope: 'finance' },
  transactions:            { label: 'Wallet Transactions',       date: 'createdAt', scope: 'finance' },
  settlements:             { label: 'Partner Settlements',       date: 'createdAt', scope: 'finance' },
  coupons:                 { label: 'Coupons',                   date: null,        scope: 'finance' },
  refunds:                 { label: 'Refunds',                   date: 'createdAt', scope: 'finance' },
  referrals:               { label: 'Referrals',                 date: 'createdAt', scope: 'finance' },
  hospital_bill_discounts: { label: 'Bill Discounts',            date: null,        scope: 'finance' },
  hospital_bill_payments:  { label: 'Hospital Bill Payments',    date: 'createdAt', scope: 'finance' },
  doctor_reviews:          { label: 'Doctor Reviews',            date: 'createdAt', scope: 'quality' },
  feedback:                { label: 'Patient Feedback',          date: 'createdAt', scope: 'quality' },
  weekly_quality_reports:  { label: 'Weekly Quality Scorecards', date: 'createdAt', scope: 'quality' },
  support_tickets:         { label: 'Support Tickets',           date: 'createdAt', scope: 'quality' },
  operation_logs:          { label: 'Operation Logs',            date: 'timestamp', scope: 'quality' },
};
const REPORT_PREFIX_SCOPE = { fr: 'finance', qr: 'quality' };
const REPORT_MAX_ROWS = 5000;

let _scopedReportsListener = null;
let _scopedReportRows = [];

function initScopedReports() {
  if (_scopedReportsListener) { renderScopedReportLists(); return; }
  _scopedReportsListener = db.collection('admin_generated_reports').orderBy('createdAt', 'desc').limit(60).onSnapshot(snap => {
    _scopedReportRows = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderScopedReportLists();
  }, err => {
    console.error('reports list error:', err);
    ['fr', 'qr'].forEach(p => {
      const el = document.getElementById(p + '-reports-list');
      if (el) el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-alert-circle"></i></div><p>Couldn\'t load reports — try refreshing.</p></div>';
    });
  });
}

function renderScopedReportLists() {
  Object.keys(REPORT_PREFIX_SCOPE).forEach(prefix => {
    const el = document.getElementById(prefix + '-reports-list');
    if (!el) return;
    const scope = REPORT_PREFIX_SCOPE[prefix];
    // Reports saved before scoping existed carry no `scope` — they were all
    // revenue/doctor/ticket queue requests, so show them under Finance.
    const rows = _scopedReportRows.filter(r => (r.scope || 'finance') === scope).slice(0, 12);
    if (!rows.length) { el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-file-analytics"></i></div><p>No reports generated yet</p></div>'; return; }
    el.innerHTML = rows.map(r => `<div class="report-row">
      <div class="report-ico"><i class="ti ti-file-spreadsheet"></i></div>
      <div class="report-meta"><div class="user-name">${escHtml(r.title || 'Report')}</div>
        <div class="user-sub">${escHtml((r.format || '').toUpperCase())}${r.rowCount != null ? ' · ' + escHtml(String(r.rowCount)) + ' rows' : ''} · ${escHtml(r.createdBy || '')} · ${escHtml(_fmtWhen(r.createdAt))}</div></div>
      ${r.collection && REPORT_SOURCES[r.collection] ? `<button class="btn btn-outline" onclick="rerunScopedReport(${escJsAttr(prefix)},${escJsAttr(r.collection)},${escJsAttr(String(r.rangeDays ?? 30))},${escJsAttr(r.format || 'csv')})"><i class="ti ti-refresh"></i> Run again</button>` : ''}
    </div>`).join('');
  });
}

function rerunScopedReport(prefix, collection, days, format) {
  const set = (id, v) => { const el = document.getElementById(prefix + '-' + id); if (el) el.value = v; };
  set('type', collection); set('range', days); set('format', format);
  generateScopedReport(prefix);
}

function _flattenDoc(obj, prefix, out, depth) {
  Object.keys(obj || {}).forEach(k => {
    const v = obj[k];
    const key = prefix ? prefix + '.' + k : k;
    if (v === null || v === undefined) { out[key] = ''; return; }
    if (typeof v.toDate === 'function') { out[key] = v.toDate().toISOString(); return; }
    if (Array.isArray(v)) { out[key] = v.map(x => (x && typeof x === 'object') ? JSON.stringify(x) : x).join('; '); return; }
    if (typeof v === 'object') {
      if (depth < 2) _flattenDoc(v, key, out, depth + 1); else out[key] = JSON.stringify(v);
      return;
    }
    out[key] = v;
  });
  return out;
}

function _download(filename, mime, content) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

async function generateScopedReport(prefix) {
  const get = id => document.getElementById(prefix + '-' + id);
  const coll = get('type').value;
  const src = REPORT_SOURCES[coll];
  if (!src || src.scope !== REPORT_PREFIX_SCOPE[prefix]) return;
  const days = parseInt(get('range').value, 10) || 0;
  const format = get('format').value;
  const btn = get('generate-btn');
  // The print window must be opened synchronously inside the click, before any await.
  const printWin = format === 'pdf' ? window.open('', '_blank') : null;
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="ti ti-loader-2 spin"></i> Generating…'; }
  try {
    const since = days > 0 ? new Date(Date.now() - days * 86400000) : null;
    let docs;
    try {
      let q = db.collection(coll);
      if (since && src.date) q = q.where(src.date, '>=', since).orderBy(src.date, 'desc');
      docs = (await q.limit(REPORT_MAX_ROWS).get()).docs;
    } catch (e) {
      // Fall back to an unfiltered read (e.g. a field that is not indexed/typed as expected).
      docs = (await db.collection(coll).limit(REPORT_MAX_ROWS).get()).docs;
      if (since && src.date) docs = docs.filter(d => _tsMillis(d.data()[src.date]) >= since.getTime());
    }
    if (!docs.length) { if (printWin) printWin.close(); showToast('No data found for this report and period.'); return; }
    const rows = docs.map(d => ({ id: d.id, ..._flattenDoc(d.data(), '', {}, 0) }));
    const cols = [];
    rows.forEach(r => Object.keys(r).forEach(k => { if (!cols.includes(k) && cols.length < 60) cols.push(k); }));
    const stamp = new Date().toISOString().slice(0, 10);
    const base = `mednu-${coll.replace(/_/g, '-')}-${stamp}`;

    if (format === 'csv') {
      const esc = v => { const t = String(v ?? ''); return /[",\n\r]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
      const csv = [cols.map(esc).join(',')].concat(rows.map(r => cols.map(c => esc(r[c])).join(','))).join('\r\n');
      _download(base + '.csv', 'text/csv;charset=utf-8', '﻿' + csv);
    } else {
      const table = '<table border="1" cellspacing="0" cellpadding="4"><thead><tr>' + cols.map(c => `<th>${escHtml(c)}</th>`).join('') + '</tr></thead><tbody>'
        + rows.map(r => '<tr>' + cols.map(c => `<td>${escHtml(String(r[c] ?? ''))}</td>`).join('') + '</tr>').join('') + '</tbody></table>';
      if (format === 'xls') {
        _download(base + '.xls', 'application/vnd.ms-excel', `<html><head><meta charset="utf-8"></head><body>${table}</body></html>`);
      } else if (printWin) {
        printWin.document.write(`<html><head><meta charset="utf-8"><title>${escHtml(src.label)}</title>
          <style>body{font:11px system-ui,sans-serif;margin:16px}h1{font-size:16px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:3px 5px;text-align:left;vertical-align:top}th{background:#f5e6f0}</style></head>
          <body><h1>MedNU — ${escHtml(src.label)}</h1><p>${rows.length} rows · generated ${escHtml(new Date().toLocaleString('en-IN'))}</p>${table}</body></html>`);
        printWin.document.close();
        printWin.focus();
        setTimeout(() => printWin.print(), 400);
      } else {
        showToast('Allow pop-ups to export a PDF.');
        return;
      }
    }
    try {
      await db.collection('admin_generated_reports').add({
        title: `${src.label} — ${days > 0 ? 'last ' + days + ' days' : 'all time'}`,
        scope: src.scope, collection: coll, type: src.label, rangeDays: days, format,
        rowCount: rows.length, status: 'ready',
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        createdBy: auth.currentUser?.email || 'admin',
      });
    } catch (e) { console.warn('report history not saved', e); }
    showToast(`${src.label} report ready — ${rows.length} rows`);
  } catch (err) {
    console.error('generateScopedReport', err);
    if (printWin) printWin.close();
    showToast('Could not generate report: ' + (err.message || 'permission denied'));
  } finally {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="ti ti-download"></i> Generate'; }
  }
}
