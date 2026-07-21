// ============================================
//   MEDNU ADMIN — MAIN APP LOGIC
//   Fetches real data from Firebase Firestore
// ============================================

// â”€â”€ Security: HTML escaping to prevent XSS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// ALWAYS call escHtml() before inserting Firestore data into innerHTML.
function escHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

// â”€â”€ Rate-limit guard (prevents double-clicking approve/reject) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _actionCooldowns = new Set();
function withCooldown(key, fn) {
  if (_actionCooldowns.has(key)) return;
  _actionCooldowns.add(key);
  fn();
  setTimeout(() => _actionCooldowns.delete(key), 3000);
}

// â”€â”€ Global unhandled rejection logger â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
window.addEventListener('unhandledrejection', event => {
  console.error('[MedNU Admin] Unhandled promise rejection:', event.reason);
  showToast('An unexpected error occurred. Check the console.');
});

// â”€â”€ Admin role verification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function verifyAdminRole(uid) {
  try {
    const adminDoc = await db.collection('admins').doc(uid).get();
    return adminDoc.exists;
  } catch (e) {
    return false;
  }
}

// ---- AUTH GUARD ----
auth.onAuthStateChanged(async user => {
  if (user) {
    // Verify the signed-in user is actually an admin
    const isAdmin = await verifyAdminRole(user.uid);
    if (!isAdmin) {
      showToast('Access denied: not an admin account.');
      await auth.signOut();
      return;
    }
    document.getElementById('login-page').style.display = 'none';
    document.getElementById('app').style.display = 'flex';
    initDashboard();
  } else {
    document.getElementById('login-page').style.display = 'flex';
    document.getElementById('app').style.display = 'none';
  }
});

// ---- LOGIN ----
document.getElementById('login-form').addEventListener('submit', async e => {
  e.preventDefault();
  const email = document.getElementById('email').value;
  const pass  = document.getElementById('password').value;
  const err   = document.getElementById('login-error');
  err.style.display = 'none';
  try {
    await auth.signInWithEmailAndPassword(email, pass);
  } catch (ex) {
    err.textContent = 'Invalid email or password.';
    err.style.display = 'block';
  }
});

// ---- LOGOUT ----
document.getElementById('logout-btn').addEventListener('click', () => auth.signOut());

// ---- NAV ----
document.querySelectorAll('.nav-item[data-tab]').forEach(item => {
  item.addEventListener('click', () => switchTab(item.dataset.tab, item.dataset.title));
});

function switchTab(tab, title) {
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.querySelector(`.nav-item[data-tab="${tab}"]`).classList.add('active');
  document.querySelectorAll('.tab-section').forEach(s => s.classList.remove('active'));
  document.getElementById(`tab-${tab}`).classList.add('active');
  document.getElementById('page-title').textContent = title || tab;
  document.getElementById('page-sub').textContent = new Date().toLocaleDateString('en-IN', { weekday:'long', year:'numeric', month:'long', day:'numeric' });

  // Always return to hub when re-entering Services
  if (tab === 'services') {
    _activeServiceCategory = null;
    const hub = document.getElementById('services-hub');
    const catView = document.getElementById('services-cat-view');
    if (hub) hub.style.display = 'block';
    if (catView) catView.style.display = 'none';
  }

  // Initialize nutrition tab when first opened
  if (tab === 'nutrition') {
    initNutritionTab();
  }

  // Initialize operation logs when tab is first opened
  if (tab === 'operation-logs') {
    initOperationLogs();
  }
}

// ---- TOAST ----
function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 3000);
}

// ============================================
//   REALTIME PRO — LIVE CLOCK
// ============================================

function initLiveClock() {
  const el = document.getElementById('clock-time');
  if (!el) return;
  const tick = () => {
    const now = new Date();
    const h = String(now.getHours()).padStart(2, '0');
    const m = String(now.getMinutes()).padStart(2, '0');
    const s = String(now.getSeconds()).padStart(2, '0');
    el.textContent = h + ':' + m + ':' + s + ' IST';
  };
  tick();
  setInterval(tick, 1000);
}
initLiveClock();

// ============================================
//   REALTIME PRO — CONNECTION STATUS MONITOR
// ============================================

function initConnectionMonitor() {
  const badge = document.getElementById('conn-status');
  if (!badge) return;

  // Firestore doesn't expose .info/connected (that's Realtime Database).
  // Instead we poll network status and do a lightweight Firestore probe.
  function setOnline() {
    badge.className = 'conn-status online';
    badge.innerHTML = '<span class="conn-dot"></span><span>Live</span>';
  }
  function setOffline() {
    badge.className = 'conn-status offline';
    badge.innerHTML = '<span class="conn-dot"></span><span>Offline</span>';
  }

  window.addEventListener('online',  setOnline);
  window.addEventListener('offline', setOffline);

  // Initial probe — try a lightweight Firestore read to confirm connectivity.
  db.collection('admins').limit(1).get()
    .then(setOnline)
    .catch(setOffline);

  // Re-probe every 30 s to catch silent disconnects.
  setInterval(() => {
    if (!navigator.onLine) { setOffline(); return; }
    db.collection('admins').limit(1).get()
      .then(setOnline)
      .catch(setOffline);
  }, 30000);
}

// ============================================
//   REALTIME PRO — COUNTER ANIMATION
// ============================================

function animateCounter(el, endVal, prefix, suffix, decimals) {
  if (!el) return;
  prefix  = prefix  || '';
  suffix  = suffix  || '';
  decimals = decimals || 0;
  const duration = 700;
  const startVal = parseFloat(el.dataset.currentVal || '0') || 0;
  if (startVal === endVal) return;

  const start = performance.now();
  const step = (now) => {
    const progress = Math.min((now - start) / duration, 1);
    const ease = 1 - Math.pow(1 - progress, 3);
    const current = startVal + (endVal - startVal) * ease;
    el.textContent = prefix + (decimals ? current.toFixed(decimals) : Math.round(current).toLocaleString('en-IN')) + suffix;
    if (progress < 1) {
      requestAnimationFrame(step);
    } else {
      el.textContent = prefix + (decimals ? endVal.toFixed(decimals) : endVal.toLocaleString('en-IN')) + suffix;
      el.dataset.currentVal = endVal;
      el.classList.add('counter-flash');
      setTimeout(() => el.classList.remove('counter-flash'), 400);
    }
  };
  requestAnimationFrame(step);
}

// Flash the parent metric-card when a stat updates
function flashMetricCard(statId) {
  const el = document.getElementById(statId);
  if (!el) return;
  const card = el.closest('.metric-card');
  if (!card) return;
  card.classList.remove('stat-updated');
  void card.offsetWidth;
  card.classList.add('stat-updated');
}

// ============================================
//   REALTIME PRO — SKELETON LOADER HELPERS
// ============================================

function skeletonRows(cols, rows) {
  rows = rows || 5;
  const widths = ['60%', '80%', '50%', '70%', '40%', '90%', '55%', '75%'];
  let html = '';
  for (let i = 0; i < rows; i++) {
    html += '<tr class="skeleton-tr">';
    for (let c = 0; c < cols; c++) {
      const w = widths[(i * cols + c) % widths.length];
      html += '<td><span class="skeleton sk-cell" style="width:' + w + ';height:11px;display:block;"></span></td>';
    }
    html += '</tr>';
  }
  return html;
}

function skeletonMetric(id) {
  const el = document.getElementById(id);
  if (el) el.innerHTML = '<span class="skeleton sk-row" style="width:70%;height:28px;display:block;"></span>';
}

// ============================================
//   REALTIME PRO — REFRESH WITH SPINNER
// ============================================

function refreshDashboard() {
  const icon = document.getElementById('refresh-icon');
  if (icon) {
    icon.style.animation = 'spin 0.7s linear infinite';
    icon.style.display = 'inline-block';
  }
  initDashboard();
  setTimeout(() => {
    if (icon) icon.style.animation = '';
    updateLastRefreshTime();
  }, 1800);
}

function updateLastRefreshTime() {
  const tag = document.getElementById('last-refresh-tag');
  const timeEl = document.getElementById('last-refresh-time');
  const now = new Date();
  const h = String(now.getHours()).padStart(2, '0');
  const m = String(now.getMinutes()).padStart(2, '0');
  const timeStr = 'Updated ' + h + ':' + m;
  if (tag && timeEl) {
    timeEl.textContent = timeStr;
    tag.style.display = 'flex';
    const divLeft = document.getElementById('topbar-div-left');
    if (divLeft) divLeft.style.display = 'block';
  }
  const csTime = document.getElementById('cs-refresh-time');
  if (csTime) csTime.textContent = timeStr;
}

// ============================================
//   REALTIME PRO — LIVE OVERVIEW STRIP
// ============================================

async function loadLiveStrip() {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const [onlineDocs, todayAppts, openTickets, ratingSnap, activeCalls] = await Promise.all([
      db.collection('doctors').where('isOnline', '==', true).get(),
      db.collection('appointments').where('createdAt', '>=', todayStart).get(),
      db.collection('support_tickets').where('status', '==', 'open').get(),
      db.collection('doctor_rating_summary').get(),
      db.collection('consultations').where('status', 'in', ['pending', 'ongoing', 'active']).get(),
    ]);

    const el = (id) => document.getElementById(id);
    if (el('strip-online-doctors')) el('strip-online-doctors').textContent = onlineDocs.size;
    if (el('strip-today-appts'))    el('strip-today-appts').textContent = todayAppts.size;
    if (el('strip-open-tickets'))   el('strip-open-tickets').textContent = openTickets.size;
    if (el('strip-active-calls'))   el('strip-active-calls').textContent = activeCalls.size;

    if (el('strip-platform-rating') && !ratingSnap.empty) {
      let totalRating = 0, totalReviews = 0;
      ratingSnap.forEach(d => {
        const dat = d.data();
        if (dat.totalReviews && dat.averageRating) {
          totalRating  += dat.averageRating * dat.totalReviews;
          totalReviews += dat.totalReviews;
        }
      });
      const avg = totalReviews > 0 ? (totalRating / totalReviews).toFixed(1) : '--';
      el('strip-platform-rating').textContent = avg + ' ★';
    }
  } catch (e) {
    console.warn('loadLiveStrip error:', e);
  }
}

// ============================================
//   OVERVIEW
// ============================================
async function loadOverview() {
  try {
    // Doctors count
    const doctorsSnap = await db.collection('doctors').get();
    animateCounter(document.getElementById('stat-doctors'), doctorsSnap.size);
    flashMetricCard('stat-doctors');

    // Patients count — reads from 'users' (same collection Flutter writes to)
    const patientsSnap = await db.collection('users').get();
    animateCounter(document.getElementById('stat-patients'), patientsSnap.size);
    flashMetricCard('stat-patients');

    // Revenue -- aggregate from multiple collections this month
    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    let totalRevenue = 0;
    try {
      const paymentsSnap = await db.collection('payments')
        .where('createdAt', '>=', startOfMonth).get();
      paymentsSnap.forEach(doc => {
        const d = doc.data();
        if (!d.status || d.status === 'completed' || d.status === 'success' || d.status === 'paid') {
          totalRevenue += d.amount || 0;
        }
      });
    } catch(e) { console.warn('payments fetch:', e.message); }
    try {
      const walletSnap = await db.collection('wallet_transactions')
        .where('createdAt', '>=', startOfMonth)
        .where('type', '==', 'credit').get();
      walletSnap.forEach(doc => {
        const d = doc.data();
        if (d.source && d.source !== 'referral' && d.source !== 'refund') {
          totalRevenue += d.amount || 0;
        }
      });
    } catch(e) { /* wallet_transactions may not exist */ }
    try {
      const consultSnap = await db.collection('consultations')
        .where('createdAt', '>=', startOfMonth)
        .where('status', '==', 'completed').get();
      consultSnap.forEach(doc => {
        const d = doc.data();
        if (d.amount && d.amount > 0 && !d.countedInPayments) totalRevenue += d.amount;
      });
    } catch(e) { /* consultations may not have amount field */ }
    const revEl = document.getElementById('stat-revenue');
    if (revEl) revEl.innerHTML = formatCurrency(totalRevenue);
    flashMetricCard('stat-revenue');

    // Open tickets
    const ticketsSnap = await db.collection('support_tickets').where('status', '==', 'open').get();
    animateCounter(document.getElementById('stat-tickets'), ticketsSnap.size);
    flashMetricCard('stat-tickets');

    // Pending doctors for quick list — fetch all and filter client-side
    // so doctors registered before the status field was introduced also appear
    const allDoctorsSnap = await db.collection('doctors').get();
    const pendingDocs = allDoctorsSnap.docs.filter(doc => {
      const s = doc.data().status;
      return !s || s === 'pending';
    }).slice(0, 5);
    renderPendingList(pendingDocs);

    // Revenue chart
    await buildRevenueChart();

    // Top medicines
    await loadTopMedicinesOverview();

    // Recent tickets
    await loadRecentTickets();

    // Secondary metrics (new)
    loadSecondaryMetrics();

    // Live activity feed (new)
    loadLiveActivityFeed();

    // Revenue summary row (new)
    updateRevenueSummaryRow();

  } catch (err) {
    console.error('Overview load error:', err);
  }
}

// ── REALTIME REVENUE LISTENER ─────────────────────────────────────────────────
let _revenueUnsubscribe = null;
function startRealtimeRevenue() {
  if (_revenueUnsubscribe) _revenueUnsubscribe();
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  _revenueUnsubscribe = db.collection('payments')
    .where('createdAt', '>=', startOfMonth)
    .onSnapshot(snap => {
      let total = 0;
      snap.forEach(doc => {
        const d = doc.data();
        if (!d.status || d.status === 'completed' || d.status === 'success' || d.status === 'paid') {
          total += d.amount || 0;
        }
      });
      const el = document.getElementById('stat-revenue');
      if (el) { el.innerHTML = formatCurrency(total); flashMetricCard('stat-revenue'); }
    }, e => console.warn('revenue listener:', e));
}


// ── SECONDARY METRICS ─────────────────────────────────────────────────────────
async function loadSecondaryMetrics() {
  const setVal = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };

  // Fetch each independently so one failure doesn't block others
  const safe = async (fn) => { try { return await fn(); } catch(e) { return null; } };

  const [hospSnap, ambSnap, refSnap, bannerSnap, matSnap, reqPendingSnap, reqAllSnap] = await Promise.all([
    safe(() => db.collection('hospitals').get()),
    safe(() => db.collection('ambulances').get()),
    safe(() => db.collection('referrals').get()),
    safe(() => db.collection('banners').get()),
    safe(() => db.collection('maternity_profiles').get()),
    safe(() => db.collection('service_requests').where('status', 'in', ['pending','accepted']).get()),
    safe(() => db.collection('service_requests').get()),
  ]);

  // Hospitals: count only enabled ones client-side (avoids composite index requirement)
  if (hospSnap) {
    const count = hospSnap.docs.filter(d => d.data().enabled !== false).length;
    setVal('sec-hospitals', count);
  }

  // Ambulances: count only enabled ones client-side
  if (ambSnap) {
    const count = ambSnap.docs.filter(d => d.data().enabled !== false).length;
    setVal('sec-ambulances', count);
  }

  // Referrals: total count
  if (refSnap) setVal('sec-referrals', refSnap.size);

  // Banners: count only active ones client-side
  if (bannerSnap) {
    const count = bannerSnap.docs.filter(d => d.data().enabled !== false).length;
    setVal('sec-banners', count);
  }

  // Maternity: try multiple collection names
  if (matSnap && matSnap.size > 0) {
    setVal('sec-maternity', matSnap.size);
  } else {
    // Try alternate collection name
    const alt = await safe(() => db.collection('maternity').get());
    setVal('sec-maternity', alt ? alt.size : 0);
  }

  // Service requests: pending + accepted
  if (reqPendingSnap) {
    setVal('sec-service-requests', reqPendingSnap.size);
    setVal('strip-emergency-count', reqPendingSnap.size);
  } else if (reqAllSnap) {
    const active = reqAllSnap.docs.filter(d => ['pending','accepted','in_progress'].includes(d.data().status)).length;
    setVal('sec-service-requests', active);
    setVal('strip-emergency-count', active);
  }
}


async function updateRevenueSummaryRow() {
  try {
    const now = new Date();
    const sixMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 5, 1);
    const snap = await db.collection('payments').where('createdAt', '>=', sixMonthsAgo).get();
    const monthly = {};
    snap.forEach(doc => {
      const d = doc.data();
      const dt = d.createdAt && d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt);
      const key = dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0');
      monthly[key] = (monthly[key] || 0) + (d.amount || 0);
    });
    const vals = Object.values(monthly);
    if (!vals.length) return;
    const total = vals.reduce((a, b) => a + b, 0);
    const avg   = total / vals.length;
    const best  = Math.max(...vals);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const bestKey = Object.keys(monthly).find(k => monthly[k] === best) || '';
    const bestLabel = bestKey ? months[parseInt(bestKey.split('-')[1]) - 1] : '--';
    const setEl = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
    setEl('rev-total-val',   formatCurrency(total));
    setEl('rev-avg-val',     formatCurrency(Math.round(avg)));
    setEl('rev-best-month',  bestLabel);
  } catch (e) {
    console.warn('updateRevenueSummaryRow error:', e);
  }
}

// ── LIVE ACTIVITY FEED ────────────────────────────────────────────────────────
let _activityItems = [];
let _activityUnsubscribers = [];

function loadLiveActivityFeed() {
  _activityUnsubscribers.forEach(u => u && u());
  _activityUnsubscribers = [];
  _activityItems = [];

  const feedEl = document.getElementById('live-activity-feed');
  if (!feedEl) return;

  function pushActivity(icon, iconBg, iconColor, text, time) {
    _activityItems.unshift({ icon, iconBg, iconColor, text, time });
    _activityItems = _activityItems.slice(0, 15);
    renderActivityFeed();
  }

  function renderActivityFeed() {
    if (!feedEl) return;
    if (!_activityItems.length) {
      feedEl.innerHTML = '<div class="empty-state" style="padding:24px;"><div class="empty-icon"><i class="ti ti-activity"></i></div><p>No recent activity</p></div>';
      return;
    }
    feedEl.innerHTML = _activityItems.map(item => `
      <div class="activity-item" style="animation:row-slide-in 0.3s ease;">
        <div class="activity-dot" style="background:${item.iconBg};width:30px;height:30px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;color:${item.iconColor};">
          <i class="ti ${item.icon}"></i>
        </div>
        <div class="activity-body">
          <div class="activity-text">${item.text}</div>
          <div class="activity-time">${item.time}</div>
        </div>
      </div>`).join('');
  }

  // Watch new appointments
  const u1 = db.collection('appointments')
    .orderBy('createdAt', 'desc').limit(5)
    .onSnapshot(snap => {
      snap.docChanges().forEach(ch => {
        if (ch.type === 'added') {
          const d = ch.doc.data();
          pushActivity('ti-calendar-check', '#e8f5e9', '#1e8e3e',
            `New appointment: ${escHtml(d.patientName||'Patient')} &rarr; Dr. ${escHtml(d.doctorName||'Doctor')}`,
            d.createdAt ? timeAgo(d.createdAt) : 'just now');
        }
      });
    }, e => console.warn('activity appointments:', e));
  _activityUnsubscribers.push(u1);

  // Watch new service requests
  const u2 = db.collection('service_requests')
    .orderBy('createdAt', 'desc').limit(5)
    .onSnapshot(snap => {
      snap.docChanges().forEach(ch => {
        if (ch.type === 'added') {
          const d = ch.doc.data();
          pushActivity('ti-clipboard-list', '#e3f2fd', '#1565c0',
            `Service request: ${escHtml(d.patientName||'Patient')} &ndash; ${escHtml(reqTypeLabel(d.type))}`,
            d.createdAt ? timeAgo(d.createdAt) : 'just now');
        }
      });
    }, e => console.warn('activity svc req:', e));
  _activityUnsubscribers.push(u2);

  // Watch new support tickets
  const u3 = db.collection('support_tickets')
    .orderBy('createdAt', 'desc').limit(5)
    .onSnapshot(snap => {
      snap.docChanges().forEach(ch => {
        if (ch.type === 'added') {
          const d = ch.doc.data();
          pushActivity('ti-headset', '#fff3e0', '#e65100',
            `Support ticket: ${escHtml(d.title||d.message||'New issue')}`,
            d.createdAt ? timeAgo(d.createdAt) : 'just now');
        }
      });
    }, e => console.warn('activity tickets:', e));
  _activityUnsubscribers.push(u3);

  // Render shimmer while loading
  if (!_activityItems.length) {
    feedEl.innerHTML = `
      <div class="activity-skeleton"><div class="skeleton sk-circle" style="width:30px;height:30px;flex-shrink:0;"></div><div style="flex:1;"><div class="skeleton sk-row" style="width:85%;height:11px;"></div><div class="skeleton sk-row" style="width:50%;height:9px;margin-top:4px;"></div></div></div>
      <div class="activity-skeleton"><div class="skeleton sk-circle" style="width:30px;height:30px;flex-shrink:0;"></div><div style="flex:1;"><div class="skeleton sk-row" style="width:70%;height:11px;"></div><div class="skeleton sk-row" style="width:40%;height:9px;margin-top:4px;"></div></div></div>
      <div class="activity-skeleton"><div class="skeleton sk-circle" style="width:30px;height:30px;flex-shrink:0;"></div><div style="flex:1;"><div class="skeleton sk-row" style="width:80%;height:11px;"></div><div class="skeleton sk-row" style="width:55%;height:9px;margin-top:4px;"></div></div></div>`;
  }
}

function renderPendingList(docs) {
  const el = document.getElementById('pending-doctors-list');
  if (!el) return;
  if (!docs.length) {
    el.innerHTML = `<div class="empty-state" style="padding:24px 0;">
      <div class="empty-icon"><i class="ti ti-circle-check" style="color:#1e8e3e;"></i></div>
      <p style="color:#1e8e3e;font-weight:600;">All clear! No pending approvals</p>
    </div>`;
    return;
  }
  el.innerHTML = docs.map(doc => {
    const d = doc.data();
    const initials = getInitials(d.name || 'DR');
    const color = randomAvatarColor();
    return `
    <div class="pending-item">
      <div class="doc-avatar" style="background:${escHtml(color.bg)};color:${escHtml(color.fg)};width:36px;height:36px;font-size:12px;">${escHtml(initials)}</div>
      <div style="flex:1;min-width:0;">
        <div class="user-name" style="font-size:13px;">${escHtml(d.name || 'Unknown')}</div>
        <div class="user-sub">${escHtml(d.specialty || d.specialisation || 'General')}</div>
      </div>
      <button class="btn btn-approve" style="font-size:11px;padding:5px 10px;" onclick="approveDoctor('${escHtml(doc.id)}', this)">
        <i class="ti ti-check"></i> Approve
      </button>
    </div>`;
  }).join('');
}

// ============================================
//   DOCTORS
// ============================================
let allDoctors = [];

async function loadDoctors() {
  const tbody = document.getElementById('doctors-tbody');
  if (tbody) tbody.innerHTML = skeletonRows(7, 6);
  try {
    const snap = await db.collection('doctors').orderBy('createdAt', 'desc').get();
    allDoctors = [];
    snap.forEach(doc => allDoctors.push({ id: doc.id, ...doc.data() }));
    renderDoctorsTable(allDoctors);
  } catch (err) {
    console.error('loadDoctors error:', err);
    if (tbody) tbody.innerHTML = '<tr><td colspan="7" class="loading" style="color:red;">Failed to load doctors. Check your connection.</td></tr>';
    showToast('Failed to load doctors list.');
  }
}

function renderDoctorsTable(doctors) {
  const tbody = document.getElementById('doctors-tbody');
  if (!doctors.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="loading">No doctors found</td></tr>';
    return;
  }
  tbody.innerHTML = doctors.map(d => {
    const initials = getInitials(d.name || 'DR');
    const color = randomAvatarColor(d.name);
    const safeStatus = (d.status || 'pending').toLowerCase();
    const isTherapist = d.type === 'therapist';
    return `<tr>
      <td><div class="user-cell">
        <div class="doc-avatar" style="background:${escHtml(color.bg)};color:${escHtml(color.fg)};">${escHtml(initials)}</div>
        <div><div class="user-name">${escHtml(d.name || '—')}</div><div class="user-sub">${escHtml(d.email || '')}</div></div>
      </div></td>
      <td><span class="svc-type-badge" style="background:${isTherapist ? '#f3e5f5' : '#e3f2fd'};color:${isTherapist ? '#6a1b9a' : '#1565c0'};">${isTherapist ? 'Therapist' : 'Doctor'}</span></td>
      <td>${escHtml(d.specialty || d.specialisation || d.specialization || '—')}</td>
      <td>${escHtml(d.phone || '—')}</td>
      <td>${escHtml(String(d.consultations || 0))}</td>
      <td>${(d.totalReviews > 0 && d.rating > 0) ? `â­ ${escHtml(d.rating.toFixed(1))} <span style="font-size:11px;color:#9E9E9E;">(${d.totalReviews})</span>` : '<span style="color:#BDBDBD;font-size:12px;">No reviews</span>'}</td>
      <td><span class="pill pill-${escHtml(safeStatus)}">${escHtml(capitalize(d.status || 'Pending'))}</span></td>
      <td>
        ${(!d.status || d.status === 'pending') ? `
          <button class="btn btn-approve" onclick="approveDoctor('${escHtml(d.id)}', this)">Approve</button>
          <button class="btn btn-reject" style="margin-left:4px;" onclick="rejectDoctor('${escHtml(d.id)}', this)">Reject</button>
        ` : `<button class="btn btn-outline" onclick="viewDoctor('${escHtml(d.id)}')">View</button>`}
        <button class="btn btn-outline" style="margin-left:4px;" onclick="editDoctorAdmin('${escHtml(d.id)}')" title="Edit">
          <i class="ti ti-edit"></i>
        </button>
      </td>
    </tr>`;
  }).join('');
}

function filterDoctorsTable() {
  const q           = (document.getElementById('doctor-search')?.value || '').toLowerCase();
  const typeFilter   = document.getElementById('doctor-type-filter')?.value || 'all';
  const statusFilter = document.getElementById('doctor-status-filter')?.value || 'all';

  let list = allDoctors;
  if (typeFilter !== 'all') list = list.filter(d => (d.type || 'doctor') === typeFilter);
  if (statusFilter !== 'all') list = list.filter(d => d.status === statusFilter);
  if (q) {
    list = list.filter(d =>
      (d.name||'').toLowerCase().includes(q) ||
      (d.specialty||d.specialisation||d.specialization||'').toLowerCase().includes(q) ||
      (d.email||'').toLowerCase().includes(q)
    );
  }
  renderDoctorsTable(list);
}

// Add / Edit Doctor / Therapist (admin form)
let _editingDoctorId = null;

const DOCTOR_SPECIALTIES = [
  'General', 'Cardiology', 'Dermatology', 'Gynaecology', 'Paediatrics',
  'ENT', 'Orthopaedics', 'Neurology', 'Ophthalmology', 'Urology',
  'Gastroenterology', 'General Surgery', 'Dental', 'Radiology', 'Oncology',
  'Nephrology', 'Endocrinology', 'Pulmonology', 'Anaesthesiology', 'Rheumatology',
];

const THERAPIST_SPECIALTIES = [
  'Psychiatry', 'Psychology', 'Counselling', 'Pediatric Psychiatry',
];

function onDoctorTypeChange() {
  const type = document.getElementById('dr-type')?.value || 'doctor';
  const specialtyEl = document.getElementById('dr-specialty');
  if (!specialtyEl) return;
  const list = type === 'therapist' ? THERAPIST_SPECIALTIES : DOCTOR_SPECIALTIES;
  const current = specialtyEl.value;
  specialtyEl.innerHTML = list.map(s => `<option value="${escHtml(s)}">${escHtml(s)}</option>`).join('');
  if (list.includes(current)) specialtyEl.value = current;
}

async function saveDoctorAdmin() {
  const name           = document.getElementById('dr-name')?.value.trim();
  const type           = document.getElementById('dr-type')?.value || 'doctor';
  const specialty      = document.getElementById('dr-specialty')?.value;
  const gender         = document.getElementById('dr-gender')?.value;
  const email          = document.getElementById('dr-email')?.value.trim();
  const phone          = document.getElementById('dr-phone')?.value.trim();
  const qualifications = document.getElementById('dr-qualifications')?.value.trim();
  const experienceRaw  = document.getElementById('dr-experience')?.value;
  const feeRaw         = document.getElementById('dr-fee')?.value;
  const isActive       = document.getElementById('dr-active')?.checked !== false;

  if (!name)      { showToast('Name is required'); return; }
  if (!specialty) { showToast('Specialty is required'); return; }
  if (!feeRaw)    { showToast('Consultation fee is required'); return; }

  const btn = document.getElementById('save-doctor-btn');
  btn.disabled = true;

  const data = {
    name, type, specialty, gender,
    email:          email          || null,
    phone:          phone          || null,
    qualifications: qualifications || null,
    experience:     experienceRaw  ? parseInt(experienceRaw, 10) : null,
    fee:            parseInt(feeRaw, 10),
    status:         isActive ? 'active' : 'suspended',
    updatedAt:      firebase.firestore.FieldValue.serverTimestamp(),
    updatedBy:      auth.currentUser?.email || 'admin',
  };

  try {
    if (_editingDoctorId) {
      await db.collection('doctors').doc(_editingDoctorId).update(data);
      showToast('Doctor updated');
    } else {
      data.createdAt          = firebase.firestore.FieldValue.serverTimestamp();
      data.isOnline           = false;
      data.isVerified         = true;
      data.rating             = 0;
      data.totalReviews       = 0;
      data.totalConsultations = 0;
      data.addedByAdmin       = true;
      await db.collection('doctors').add(data);
      showToast(type === 'therapist' ? 'Therapist added' : 'Doctor added');
    }
    cancelDoctorEdit();
    loadDoctors();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    btn.disabled = false;
  }
}

function editDoctorAdmin(id) {
  const d = allDoctors.find(x => x.id === id);
  if (!d) return;
  _editingDoctorId = id;
  document.getElementById('dr-name').value           = d.name           || '';
  document.getElementById('dr-type').value           = d.type           || 'doctor';
  onDoctorTypeChange();
  document.getElementById('dr-specialty').value      = d.specialty      || '';
  document.getElementById('dr-gender').value         = d.gender         || 'Male';
  document.getElementById('dr-email').value          = d.email          || '';
  document.getElementById('dr-phone').value          = d.phone          || '';
  document.getElementById('dr-qualifications').value = d.qualifications || '';
  document.getElementById('dr-experience').value     = d.experience != null ? d.experience : '';
  document.getElementById('dr-fee').value            = d.fee != null ? d.fee : '';
  document.getElementById('dr-active').checked       = d.status === 'active';
  document.getElementById('doctor-form-title').textContent = 'Edit Doctor / Therapist';
  document.getElementById('cancel-doctor-btn').style.display = 'inline-flex';
  document.getElementById('dr-name').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function cancelDoctorEdit() {
  _editingDoctorId = null;
  ['dr-name','dr-email','dr-phone','dr-qualifications','dr-experience','dr-fee']
    .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
  document.getElementById('dr-type').value = 'doctor';
  onDoctorTypeChange();
  document.getElementById('dr-gender').value = 'Male';
  document.getElementById('dr-active').checked = true;
  document.getElementById('doctor-form-title').textContent = 'Add Doctor / Therapist';
  document.getElementById('cancel-doctor-btn').style.display = 'none';
}

async function approveDoctor(id, btn) {
  withCooldown(`approve-${id}`, async () => {
    btn.disabled = true; btn.textContent = '...';
    try {
      await db.collection('doctors').doc(id).update({
        status: 'active',
        approvedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      showToast('Doctor approved successfully!');
      loadDoctors(); loadOverview();
    } catch (err) {
      console.error('approveDoctor error:', err);
      btn.disabled = false; btn.textContent = 'Approve';
      showToast('Failed to approve doctor. Please try again.');
    }
  });
}

async function rejectDoctor(id, btn) {
  withCooldown(`reject-${id}`, async () => {
    btn.disabled = true; btn.textContent = '...';
    try {
      await db.collection('doctors').doc(id).update({
        status: 'suspended',
        rejectedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      showToast('Doctor rejected.');
      loadDoctors();
    } catch (err) {
      console.error('rejectDoctor error:', err);
      btn.disabled = false; btn.textContent = 'Reject';
      showToast('Failed to reject doctor. Please try again.');
    }
  });
}

function viewDoctor(id) {
  const d = allDoctors.find(x => x.id === id);
  if (!d) return;
  showDoctorModal(d);
}

function showDoctorModal(d) {
  // Remove existing modal if any
  document.getElementById('doctor-modal')?.remove();

  const docs = d.documents || {};
  const docKeys = {
    mbbs_degree:   'MBBS Degree Certificate',
    spec_cert:     'Specialization Certificate',
    mbbs_reg_cert: 'MBBS Registration Certificate',
    renewal_cert:  'Renewal Certificate',
    profile_photo: 'Profile Photo',
  };

  const docHtml = Object.entries(docKeys).map(([key, label]) => {
    const url = docs[key];
    return url
      ? `<div style="margin-bottom:10px;">
           <div style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:4px;">${label}</div>
           <a href="${url}" target="_blank" style="display:inline-flex;align-items:center;gap:6px;padding:6px 12px;background:var(--primary-light,#f3e5f5);color:var(--primary,#880E4F);border-radius:8px;font-size:13px;font-weight:600;text-decoration:none;">
             <span> View Document
           </a>
         </div>`
      : `<div style="margin-bottom:10px;">
           <div style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:4px;">${label}</div>
           <span style="font-size:12px;color:#aaa;font-style:italic;">Not uploaded</span>
         </div>`;
  }).join('');

  const isPending = !d.status || d.status === 'pending';

  const modal = document.createElement('div');
  modal.id = 'doctor-modal';
  modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px;';
  modal.innerHTML = `
    <div style="background:#fff;border-radius:20px;width:100%;max-width:540px;max-height:90vh;overflow-y:auto;padding:28px;">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;">
        <h2 style="font-size:18px;font-weight:700;margin:0;">Doctor Profile</h2>
        <button onclick="document.getElementById('doctor-modal').remove()"
          style="border:none;background:none;font-size:22px;cursor:pointer;color:#666;">&times;</button>
      </div>

      <div style="display:flex;align-items:center;gap:14px;padding:16px;background:#f9f9f9;border-radius:14px;margin-bottom:20px;">
        <div style="width:56px;height:56px;border-radius:50%;background:linear-gradient(135deg,#522546,#8B3A6B);display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:700;color:#fff;">${getInitials(d.name||'DR')}</div>
        <div>
          <div style="font-size:16px;font-weight:700;">${d.name||'—'}</div>
          <div style="font-size:13px;color:#888;">${d.specialty||d.specialisation||'—'} &middot; ${d.experience||'—'} yrs</div>
          <div style="font-size:12px;color:#aaa;margin-top:2px;">${d.phone||''} ${d.email ? '&middot; '+d.email : ''}</div>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:20px;">
        ${[['Reg. Number', d.registrationNumber||'—'],['Qualifications', d.qualifications||'—'],['Fee', d.fee ? '₹'+d.fee : '—'],['Gender', d.gender||'—']].map(([l,v])=>`
          <div style="padding:12px;background:#f9f9f9;border-radius:10px;">
            <div style="font-size:11px;color:#aaa;font-weight:600;text-transform:uppercase;">${l}</div>
            <div style="font-size:14px;font-weight:600;margin-top:2px;">${v}</div>
          </div>`).join('')}
      </div>

      <div style="margin-bottom:20px;">
        <div style="font-size:14px;font-weight:700;margin-bottom:12px;"> Submitted Documents</div>
        ${docHtml}
      </div>

      <div style="display:flex;gap:10px;margin-bottom:8px;">
        ${isPending ? `
          <button onclick="approveFromModal('${d.id}')" style="flex:1;padding:12px;background:#2e7d32;color:#fff;border:none;border-radius:12px;font-size:14px;font-weight:700;cursor:pointer;">âœ“ Approve Doctor</button>
          <button onclick="rejectFromModal('${d.id}')" style="flex:1;padding:12px;background:#c62828;color:#fff;border:none;border-radius:12px;font-size:14px;font-weight:700;cursor:pointer;">âœ• Reject Doctor</button>
        ` : `
          <div style="flex:1;padding:12px;text-align:center;border-radius:12px;font-weight:700;font-size:14px;background:${d.status==='active'?'#e8f5e9':'#fce4ec'};color:${d.status==='active'?'#2e7d32':'#c62828'};">
            Status: ${d.status==='active'?'âœ“ Approved':'âœ• Rejected'}
          </div>
        `}
      </div>
    </div>`;
  document.body.appendChild(modal);
  modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
}

async function approveFromModal(id) {
  try {
    await db.collection('doctors').doc(id).update({
      status: 'active',
      approvedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast('Doctor approved successfully!');
    document.getElementById('doctor-modal')?.remove();
  } catch (err) {
    console.error('approveFromModal error:', err);
    showToast('Failed to approve doctor. Please try again.');
  }
}

async function rejectFromModal(id) {
  if (!confirm('Are you sure you want to reject this doctor application?')) return;
  try {
    await db.collection('doctors').doc(id).update({
      status: 'suspended',
      rejectedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast('Doctor application rejected.');
    document.getElementById('doctor-modal')?.remove();
  } catch (err) {
    console.error('rejectFromModal error:', err);
    showToast('Failed to reject doctor. Please try again.');
  }
}

// ============================================
//   DOCTOR SPECIALIZATION REQUESTS
// ============================================
let allSpecRequests = [];
let _srListener = null;

function loadSpecRequests() {
  if (_srListener) _srListener();
  _srListener = db.collection('doctor_specialization_requests')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      allSpecRequests = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      _updateSrStats();
      filterSpecRequests();
    }, err => console.error('Spec requests load error:', err));
}

function _updateSrStats() {
  const pending  = allSpecRequests.filter(r => r.status === 'pending').length;
  const review   = allSpecRequests.filter(r => r.status === 'under_review').length;
  const approved = allSpecRequests.filter(r => r.status === 'approved').length;
  const rejected = allSpecRequests.filter(r => r.status === 'rejected').length;

  const _srPending  = document.getElementById('sr-count-pending');  if (_srPending)  _srPending.textContent  = pending;
  const _srReview   = document.getElementById('sr-count-review');   if (_srReview)   _srReview.textContent   = review;
  const _srApproved = document.getElementById('sr-count-approved'); if (_srApproved) _srApproved.textContent = approved;
  const _srRejected = document.getElementById('sr-count-rejected'); if (_srRejected) _srRejected.textContent = rejected;

  const actionable = pending + review;
  const badge = document.getElementById('nav-spec-requests-count');
  if (badge) {
    badge.textContent   = actionable;
    badge.style.display = actionable > 0 ? 'inline-flex' : 'none';
  }
}

function filterSpecRequests() {
  const q      = (document.getElementById('sr-search')?.value || '').toLowerCase();
  const status = document.getElementById('sr-status-filter')?.value || 'all';
  let list = [...allSpecRequests];
  if (status !== 'all') list = list.filter(r => r.status === status);
  if (q) list = list.filter(r =>
    (r.doctorName || '').toLowerCase().includes(q) ||
    (r.oldSpecialization || '').toLowerCase().includes(q) ||
    (r.requestedSpecialization || '').toLowerCase().includes(q)
  );
  renderSpecRequestsTable(list);
}

document.getElementById('sr-search')?.addEventListener('input', filterSpecRequests);
document.getElementById('sr-status-filter')?.addEventListener('change', filterSpecRequests);

function renderSpecRequestsTable(list) {
  const tbody = document.getElementById('sr-tbody');
  if (!tbody) return;
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="loading">No specialization requests found</td></tr>';
    return;
  }

  tbody.innerHTML = list.map(r => {
    const initials = getInitials(r.doctorName || 'DR');
    const color    = randomAvatarColor(r.doctorName);
    const docCount = (r.documents || []).length;
    const date     = r.createdAt?.toDate
      ? r.createdAt.toDate().toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
      : '—';

    const statusCfg = {
      pending:      { cls: 'pending',   label: 'Pending' },
      under_review: { cls: 'warning',   label: 'Under Review' },
      approved:     { cls: 'active',    label: 'Approved' },
      rejected:     { cls: 'suspended', label: 'Rejected' },
    };
    const sc = statusCfg[r.status] || statusCfg.pending;

    const isPending = r.status === 'pending' || r.status === 'under_review';

    return `<tr>
      <td><div class="user-cell">
        <div class="doc-avatar" style="background:${color.bg};color:${color.fg};">${initials}</div>
        <div><div class="user-name">${r.doctorName || '—'}</div></div>
      </div></td>
      <td><span style="font-size:13px;color:var(--text-secondary);">${r.oldSpecialization || '—'}</span></td>
      <td><strong style="color:var(--primary);">${r.requestedSpecialization || '—'}</strong></td>
      <td>
        <span style="display:inline-flex;align-items:center;gap:4px;font-size:13px;">
          <span> ${docCount} doc${docCount !== 1 ? 's' : ''}
        </span>
      </td>
      <td style="font-size:12px;color:var(--text-secondary);">${date}</td>
      <td><span class="pill pill-${sc.cls}">${sc.label}</span></td>
      <td>
        <button class="btn btn-outline" onclick="viewSpecRequest('${r.id}')" style="margin-right:4px;">View</button>
        ${isPending ? `
          <button class="btn btn-approve" onclick="approveSpecRequest('${r.id}', this)">Approve</button>
          <button class="btn btn-reject" onclick="promptRejectSpecRequest('${r.id}')" style="margin-left:4px;">Reject</button>
        ` : ''}
      </td>
    </tr>`;
  }).join('');
}

function viewSpecRequest(id) {
  const r = allSpecRequests.find(x => x.id === id);
  if (!r) return;

  document.getElementById('sr-modal')?.remove();

  const docHtml = (r.documents || []).map(d => `
    <div style="display:flex;align-items:center;gap:10px;padding:10px;background:#f9f9f9;border-radius:10px;margin-bottom:8px;">
      <span style="font-size:18px;">${(d.name||'').endsWith('.pdf') ? '' : ''}</span>
      <div style="flex:1;min-width:0;">
        <div style="font-size:12px;font-weight:600;color:var(--text-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${d.name || 'Document'}</div>
      </div>
      <a href="${d.url}" target="_blank" style="padding:5px 10px;background:var(--primary-light,#f3e5f5);color:var(--primary,#880E4F);border-radius:8px;font-size:12px;font-weight:600;text-decoration:none;white-space:nowrap;">View â†—</a>
    </div>
  `).join('') || '<p style="color:#aaa;font-size:13px;font-style:italic;">No documents uploaded</p>';

  const date = r.createdAt?.toDate
    ? r.createdAt.toDate().toLocaleDateString('en-IN', { weekday:'long', day:'2-digit', month:'long', year:'numeric' })
    : '—';

  const statusColors = {
    pending:      { bg:'#E3F2FD', color:'#1565C0' },
    under_review: { bg:'#FFF8E1', color:'#F57F17' },
    approved:     { bg:'#E8F5E9', color:'#2E7D32' },
    rejected:     { bg:'#FFEBEE', color:'#C62828' },
  };
  const sc = statusColors[r.status] || statusColors.pending;
  const statusLabel = { pending:'Pending Approval', under_review:'Under Review', approved:'Approved', rejected:'Rejected' }[r.status] || 'Pending';

  const isPending = r.status === 'pending' || r.status === 'under_review';
  const remarksHtml = r.adminRemarks
    ? `<div style="margin-top:14px;padding:12px;background:#fff8e1;border-radius:10px;border:1px solid #ffe082;">
         <div style="font-size:11px;font-weight:700;color:#f57f17;text-transform:uppercase;margin-bottom:4px;">Admin Remarks</div>
         <div style="font-size:13px;color:var(--text-primary);">${r.adminRemarks}</div>
       </div>`
    : '';

  const modal = document.createElement('div');
  modal.id = 'sr-modal';
  modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px;';
  modal.innerHTML = `
    <div style="background:#fff;border-radius:20px;width:100%;max-width:560px;max-height:90vh;overflow-y:auto;padding:28px;">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;">
        <h2 style="font-size:18px;font-weight:700;margin:0;">Specialization Change Request</h2>
        <button onclick="document.getElementById('sr-modal').remove()" style="border:none;background:none;font-size:22px;cursor:pointer;color:#666;">&times;</button>
      </div>

      <!-- Status badge -->
      <div style="display:inline-flex;align-items:center;gap:8px;padding:8px 16px;border-radius:20px;background:${sc.bg};margin-bottom:20px;">
        <span style="width:8px;height:8px;border-radius:50%;background:${sc.color};display:inline-block;"></span>
        <span style="font-size:13px;font-weight:700;color:${sc.color};">${statusLabel}</span>
      </div>

      <!-- Doctor info -->
      <div style="display:flex;align-items:center;gap:14px;padding:16px;background:#f9f9f9;border-radius:14px;margin-bottom:20px;">
        <div style="width:50px;height:50px;border-radius:50%;background:linear-gradient(135deg,#522546,#8B3A6B);display:flex;align-items:center;justify-content:center;font-size:18px;font-weight:700;color:#fff;">${getInitials(r.doctorName||'DR')}</div>
        <div>
          <div style="font-size:15px;font-weight:700;">${r.doctorName || '—'}</div>
          <div style="font-size:12px;color:#888;margin-top:2px;">Submitted: ${date}</div>
        </div>
      </div>

      <!-- Spec change -->
      <div style="display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:12px;margin-bottom:20px;">
        <div style="padding:14px;background:#f9f9f9;border-radius:12px;text-align:center;">
          <div style="font-size:10px;font-weight:700;color:#aaa;text-transform:uppercase;margin-bottom:6px;">Current</div>
          <div style="font-size:14px;font-weight:700;color:var(--text-primary);">${r.oldSpecialization || '—'}</div>
        </div>
        <div style="font-size:22px;color:#888;">â†’</div>
        <div style="padding:14px;background:#f3e5f5;border-radius:12px;text-align:center;border:2px solid var(--primary,#880E4F)20;">
          <div style="font-size:10px;font-weight:700;color:var(--primary,#880E4F);text-transform:uppercase;margin-bottom:6px;">Requested</div>
          <div style="font-size:14px;font-weight:700;color:var(--primary,#880E4F);">${r.requestedSpecialization || '—'}</div>
        </div>
      </div>

      <!-- Documents -->
      <div style="margin-bottom:20px;">
        <div style="font-size:14px;font-weight:700;margin-bottom:12px;"> Supporting Documents (${(r.documents||[]).length})</div>
        ${docHtml}
      </div>

      ${remarksHtml}

      <!-- Action buttons -->
      ${isPending ? `
        <div style="margin-top:20px;">
          <div style="display:flex;gap:10px;margin-bottom:10px;">
            <button onclick="approveSpecRequestFromModal('${r.id}')" style="flex:1;padding:13px;background:#2e7d32;color:#fff;border:none;border-radius:12px;font-size:14px;font-weight:700;cursor:pointer;">âœ“ Approve & Update Specialization</button>
          </div>
          <div style="display:flex;gap:10px;">
            <button onclick="setSpecRequestUnderReview('${r.id}')" style="flex:1;padding:13px;background:#e65100;color:#fff;border:none;border-radius:12px;font-size:14px;font-weight:700;cursor:pointer;"> Mark Under Review</button>
            <button onclick="promptRejectSpecRequestFromModal('${r.id}')" style="flex:1;padding:13px;background:#c62828;color:#fff;border:none;border-radius:12px;font-size:14px;font-weight:700;cursor:pointer;">âœ• Reject</button>
          </div>
        </div>
      ` : ''}
    </div>`;
  document.body.appendChild(modal);
  modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
}

async function approveSpecRequest(id, btn) {
  if (!confirm('Approve this specialization change? This will update the doctor\'s specialization immediately.')) return;
  btn.disabled = true; btn.textContent = '...';
  await _doApproveSpecRequest(id);
}

async function approveSpecRequestFromModal(id) {
  if (!confirm('Approve this specialization change? This will update the doctor\'s specialization immediately.')) return;
  document.getElementById('sr-modal')?.remove();
  await _doApproveSpecRequest(id);
}

async function _doApproveSpecRequest(id) {
  const r = allSpecRequests.find(x => x.id === id);
  if (!r) return;
  try {
    const batch = db.batch();
    // Update the request status
    batch.update(db.collection('doctor_specialization_requests').doc(id), {
      status: 'approved',
      approvedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    // Update the doctor's actual specialization
    batch.update(db.collection('doctors').doc(r.doctorId), {
      specialty:       r.requestedSpecialization,
      specialisation:  r.requestedSpecialization,
      updatedAt:       firebase.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    showToast(`Specialization approved! Doctor is now a ${r.requestedSpecialization}.`);
  } catch (err) {
    showToast('Error: ' + err.message);
  }
}

async function setSpecRequestUnderReview(id) {
  document.getElementById('sr-modal')?.remove();
  await db.collection('doctor_specialization_requests').doc(id).update({ status: 'under_review' });
  showToast('Request marked as Under Review.');
}

function promptRejectSpecRequest(id) {
  const r = allSpecRequests.find(x => x.id === id);
  if (!r) return;
  _showRejectDialog(id, r);
}

function promptRejectSpecRequestFromModal(id) {
  document.getElementById('sr-modal')?.remove();
  const r = allSpecRequests.find(x => x.id === id);
  if (!r) return;
  _showRejectDialog(id, r);
}

function _showRejectDialog(id, r) {
  document.getElementById('sr-reject-dialog')?.remove();
  const dialog = document.createElement('div');
  dialog.id = 'sr-reject-dialog';
  dialog.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:10000;display:flex;align-items:center;justify-content:center;padding:16px;';
  dialog.innerHTML = `
    <div style="background:#fff;border-radius:16px;width:100%;max-width:420px;padding:24px;">
      <h3 style="font-size:16px;font-weight:700;margin:0 0 6px;">Reject Specialization Request</h3>
      <p style="font-size:13px;color:#666;margin:0 0 16px;">Please provide a reason. The doctor will be notified.</p>
      <textarea id="sr-reject-reason" placeholder="e.g. Documents are not clear, please resubmit..." rows="4"
        style="width:100%;padding:10px 12px;border:1px solid #e0e0e0;border-radius:10px;font-family:inherit;font-size:13px;resize:none;box-sizing:border-box;"></textarea>
      <div style="display:flex;gap:10px;margin-top:14px;">
        <button onclick="document.getElementById('sr-reject-dialog').remove()"
          style="flex:1;padding:11px;border:1px solid #e0e0e0;background:#fff;border-radius:10px;font-size:13px;font-weight:600;cursor:pointer;">Cancel</button>
        <button onclick="_submitRejectSpecRequest('${id}')"
          style="flex:1;padding:11px;background:#c62828;color:#fff;border:none;border-radius:10px;font-size:13px;font-weight:700;cursor:pointer;">Reject Request</button>
      </div>
    </div>`;
  document.body.appendChild(dialog);
}

async function _submitRejectSpecRequest(id) {
  const reason = (document.getElementById('sr-reject-reason')?.value || '').trim();
  if (!reason) { alert('Please enter a rejection reason.'); return; }
  document.getElementById('sr-reject-dialog')?.remove();
  try {
    await db.collection('doctor_specialization_requests').doc(id).update({
      status: 'rejected',
      adminRemarks: reason,
    });
    showToast('Request rejected. Doctor has been notified.');
  } catch (err) {
    showToast('Error: ' + err.message);
  }
}

// Doctors search & filter
document.getElementById('doctor-search')?.addEventListener('input', filterDoctorsTable);
document.getElementById('doctor-type-filter')?.addEventListener('change', filterDoctorsTable);
document.getElementById('doctor-status-filter')?.addEventListener('change', filterDoctorsTable);

// Populate the add-doctor specialty dropdown on load
onDoctorTypeChange();

// ============================================
//   PATIENTS  (real-time — reads from 'users' collection)
// ============================================
let allPatients = [];
let _patientsListener = null;

function loadPatients() {
  if (_patientsListener) _patientsListener();
  _patientsListener = db.collection('users')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      allPatients = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      filterPatients();
      buildPatientChart(allPatients);
      // keep overview stat in sync
      document.getElementById('stat-patients').textContent = allPatients.length.toLocaleString();
    }, err => console.error('Patients load error:', err));
}

function filterPatients() {
  const q = (document.getElementById('patient-search')?.value || '').toLowerCase();
  const filtered = q
    ? allPatients.filter(p =>
        (p.name  || '').toLowerCase().includes(q) ||
        (p.phone || '').toLowerCase().includes(q) ||
        (p.email || '').toLowerCase().includes(q))
    : allPatients;
  renderPatientsTable(filtered);
}

function calcAge(dob) {
  if (!dob) return '—';
  // supports DD/MM/YYYY or YYYY-MM-DD
  let d;
  if (/^\d{2}\/\d{2}\/\d{4}$/.test(dob)) {
    const [dd, mm, yyyy] = dob.split('/');
    d = new Date(`${yyyy}-${mm}-${dd}`);
  } else {
    d = new Date(dob);
  }
  if (isNaN(d)) return '—';
  const diff = Date.now() - d.getTime();
  return Math.floor(diff / (365.25 * 24 * 3600 * 1000)) + ' yrs';
}

function renderPatientsTable(patients) {
  const tbody = document.getElementById('patients-tbody');
  if (!patients.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="loading">No patients found</td></tr>';
    return;
  }
  tbody.innerHTML = patients.map(p => {
    const initials = getInitials(p.name || 'PT');
    const color = randomAvatarColor(p.name);
    return `<tr>
      <td><div class="user-cell">
        <div class="doc-avatar" style="background:${color.bg};color:${color.fg};">${initials}</div>
        <div><div class="user-name">${p.name || '—'}</div><div class="user-sub">${p.email || ''}</div></div>
      </div></td>
      <td>${p.phone || '—'}</td>
      <td>${calcAge(p.dob)}</td>
      <td>${p.gender || '—'}</td>
      <td>${p.isPremium ? 'â­ Premium' : 'Free'}</td>
      <td>${formatDate(p.createdAt)}</td>
    </tr>`;
  }).join('');
}

document.getElementById('patient-search')?.addEventListener('input', filterPatients);

// ============================================
//   REVENUE
// ============================================
async function loadRevenue() {
  const snap = await db.collection('payments').orderBy('createdAt', 'desc').get();
  const payments = [];
  snap.forEach(doc => payments.push({ id: doc.id, ...doc.data() }));
  renderPaymentsTable(payments);
  buildRevenueDetailChart(payments);
}

function renderPaymentsTable(payments) {
  const tbody = document.getElementById('payments-tbody');
  if (!payments.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="loading">No payments found</td></tr>';
    return;
  }
  tbody.innerHTML = payments.slice(0, 50).map(p => `<tr>
    <td>${p.paymentId || p.id}</td>
    <td>${p.patientName || '—'}</td>
    <td>${p.doctorName || '—'}</td>
    <td>${formatCurrency(p.amount || 0)}</td>
    <td><span class="pill ${p.status === 'success' ? 'pill-active' : 'pill-pending'}">${capitalize(p.status||'pending')}</span></td>
    <td>${formatDate(p.createdAt)}</td>
  </tr>`).join('');
}

// ============================================
//   MEDICINES
// ============================================
async function loadMedicines() {
  const snap = await db.collection('prescriptions').get();
  const medicineCount = {};
  snap.forEach(doc => {
    const meds = doc.data().medicines || [];
    meds.forEach(m => {
      const name = m.name || m;
      medicineCount[name] = (medicineCount[name] || 0) + 1;
    });
  });
  const sorted = Object.entries(medicineCount).sort((a,b) => b[1]-a[1]).slice(0, 15);
  renderMedicinesTable(sorted);
  buildMedicinesChart(sorted.slice(0,8));
}

async function loadTopMedicinesOverview() {
  const snap = await db.collection('prescriptions').get();
  const medicineCount = {};
  snap.forEach(doc => {
    const meds = doc.data().medicines || [];
    meds.forEach(m => {
      const name = m.name || m;
      medicineCount[name] = (medicineCount[name] || 0) + 1;
    });
  });
  const sorted = Object.entries(medicineCount).sort((a,b) => b[1]-a[1]).slice(0, 5);
  const colors = ['#522546','#2E7D32','#F57F17','#C62828','#8B3A6B'];
  const el = document.getElementById('top-medicines-list');
  if (!sorted.length) { el.innerHTML = '<div class="empty-state"><p>No prescription data</p></div>'; return; }
  const max = sorted[0][1];
  el.innerHTML = sorted.map(([name, count], i) => `
    <div class="mini-bar-row">
      <span class="mini-bar-label">${escHtml(name)}</span>
      <div class="mini-bar-wrap"><div class="mini-bar-fill" style="width:${Math.round(count/max*100)}%;background:${colors[i]};"></div></div>
      <span class="mini-bar-count">${count.toLocaleString()}</span>
    </div>`).join('');
}

function renderMedicinesTable(sorted) {
  const tbody = document.getElementById('medicines-tbody');
  if (!sorted.length) { tbody.innerHTML = '<tr><td colspan="3" class="loading">No prescription data</td></tr>'; return; }
  const max = sorted[0][1];
  tbody.innerHTML = sorted.map(([name, count], i) => `<tr>
    <td>${i+1}</td>
    <td>${escHtml(name)}</td>
    <td>
      <div style="display:flex;align-items:center;gap:8px;">
        <div style="flex:1;height:6px;background:var(--border);border-radius:99px;overflow:hidden;">
          <div style="width:${Math.round(count/max*100)}%;height:100%;background:#522546;border-radius:99px;"></div>
        </div>
        <span style="font-size:12px;color:var(--text-muted);min-width:36px;">${count.toLocaleString()}</span>
      </div>
    </td>
  </tr>`).join('');
}

// ============================================
//   PRESCRIPTION LOOKUP
// ============================================

async function lookupPrescription() {
  const input = document.getElementById('rx-lookup-input');
  const statusEl = document.getElementById('rx-lookup-status');
  const resultCard = document.getElementById('rx-result-card');

  const rxId = (input?.value || '').trim().toUpperCase();
  if (!rxId) { if (statusEl) statusEl.textContent = 'Please enter an Rx ID.'; return; }

  if (statusEl) statusEl.innerHTML = '<i class="ti ti-loader-2" style="animation:spin 1s linear infinite;"></i> Searching…';
  if (resultCard) resultCard.style.display = 'none';

  try {
    const snap = await db.collection('prescriptions').where('rxId', '==', rxId).limit(1).get();
    if (snap.empty) {
      if (statusEl) statusEl.innerHTML =
        '<span style="color:var(--danger);"><i class="ti ti-circle-x"></i> No prescription found with Rx ID: <strong>' + escHtml(rxId) + '</strong></span>';
      return;
    }
    if (statusEl) statusEl.innerHTML =
      '<span style="color:var(--success);"><i class="ti ti-circle-check"></i> Prescription found.</span>';
    renderPrescriptionResult(snap.docs[0].data());
  } catch (e) {
    if (statusEl) statusEl.innerHTML = '<span style="color:var(--danger);">Error: ' + escHtml(String(e)) + '</span>';
  }
}

function clearPrescriptionLookup() {
  const input = document.getElementById('rx-lookup-input');
  const statusEl = document.getElementById('rx-lookup-status');
  const resultCard = document.getElementById('rx-result-card');
  if (input) input.value = '';
  if (statusEl) statusEl.textContent = '';
  if (resultCard) resultCard.style.display = 'none';
}

function renderPrescriptionResult(rx) {
  const resultCard = document.getElementById('rx-result-card');
  const rxIdEl = document.getElementById('rx-result-id');
  if (rxIdEl) rxIdEl.textContent = 'Rx  ' + (rx.rxId || '—');

  const pill = document.getElementById('rx-result-status-pill');
  if (pill) {
    pill.className = 'pill ' + (rx.status === 'active' ? 'pill-active' : 'pill-pending');
    pill.textContent = rx.status || 'active';
  }

  setText('rx-doctor-name', 'Dr. ' + (rx.doctorName || '—'));
  setText('rx-doctor-spec', rx.doctorSpecialty || '');
  setText('rx-doctor-reg', rx.doctorRegNo ? 'Reg. No: ' + rx.doctorRegNo : '');
  setText('rx-doctor-hospital', rx.doctorHospital || '');
  setText('rx-patient-name', rx.patientName || '—');
  const info = [rx.patientAge, rx.patientGender].filter(Boolean).join('  •  ');
  setText('rx-patient-info', info);
  setText('rx-patient-phone', rx.patientPhone ? '📞 ' + rx.patientPhone : '');

  const dateEl = document.getElementById('rx-date');
  if (dateEl) dateEl.textContent = rx.createdAt ? formatDate(rx.createdAt) : '—';

  setText('rx-diagnosis', rx.diagnosis || '—');

  const cWrap = document.getElementById('rx-complaints-wrap');
  if (cWrap) { cWrap.style.display = rx.chiefComplaints ? 'block' : 'none'; setText('rx-complaints', rx.chiefComplaints || ''); }

  const tbody = document.getElementById('rx-medicines-tbody');
  if (tbody) {
    const meds = rx.medicines || [];
    if (!meds.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="padding:10px;color:var(--text-muted);">No medicines</td></tr>';
    } else {
      tbody.innerHTML = meds.map((m, i) => {
        const name = (m.medicineName || m.name || '').toUpperCase();
        const strength = m.strength || m.dosage || '';
        const dose = [m.morning && 'M', m.afternoon && 'A', m.night && 'N'].filter(Boolean).join('-') || m.frequency || '';
        const bg = i % 2 === 1 ? 'background:#fafafa;' : '';
        return `<tr style="${bg}">
          <td style="padding:7px 10px;">${i + 1}</td>
          <td style="padding:7px 10px;font-weight:600;">${escHtml(name)}</td>
          <td style="padding:7px 10px;">${escHtml(strength)}</td>
          <td style="padding:7px 10px;">${escHtml(dose)}</td>
          <td style="padding:7px 10px;">${escHtml(m.duration || '')}</td>
          <td style="padding:7px 10px;">${escHtml(m.foodTiming || m.timing || '')}</td>
        </tr>`;
      }).join('');
    }
  }

  const invWrap = document.getElementById('rx-investigations-wrap');
  const invEl = document.getElementById('rx-investigations');
  const invs = rx.investigations || [];
  if (invWrap && invEl) {
    invWrap.style.display = invs.length ? 'block' : 'none';
    invEl.innerHTML = invs.map(inv =>
      `<span style="background:#e0f7fa;color:#00838F;border:1px solid #b2ebf2;border-radius:6px;padding:4px 10px;font-size:12px;font-weight:600;">${escHtml(inv)}</span>`
    ).join('');
  }

  const instrWrap = document.getElementById('rx-instructions-wrap');
  if (instrWrap) { instrWrap.style.display = rx.specialInstructions ? 'block' : 'none'; setText('rx-instructions', rx.specialInstructions || ''); }

  const fuWrap = document.getElementById('rx-followup-wrap');
  if (fuWrap) {
    fuWrap.style.display = rx.followUpRequired ? 'block' : 'none';
    setText('rx-followup-days', rx.followUpDays ? 'Visit after ' + rx.followUpDays + ' days' : '');
  }

  const sigWrap = document.getElementById('rx-signature-wrap');
  const sigImg = document.getElementById('rx-signature-img');
  if (sigWrap && sigImg) {
    if (rx.doctorSignatureUrl) { sigImg.src = rx.doctorSignatureUrl; sigWrap.style.display = 'block'; }
    else { sigWrap.style.display = 'none'; }
  }

  if (resultCard) resultCard.style.display = 'block';
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

// ============================================
//   SUPPORT TICKETS
// ============================================
let allTickets = [];

async function loadTickets() {
  const snap = await db.collection('support_tickets').orderBy('createdAt', 'desc').get();
  allTickets = [];
  snap.forEach(doc => allTickets.push({ id: doc.id, ...doc.data() }));
  renderTicketsTable(allTickets);
  document.getElementById('stat-tickets').textContent = allTickets.filter(t => t.status === 'open').length;
}

async function loadRecentTickets() {
  const snap = await db.collection('support_tickets').where('status','==','open').orderBy('createdAt','desc').limit(4).get();
  const el = document.getElementById('recent-tickets');
  if (!el) return;
  if (snap.empty) {
    el.innerHTML = '<div class="empty-state" style="padding:24px 0;"><div class="empty-icon"><i class="ti ti-circle-check" style="color:#1e8e3e;"></i></div><p style="color:#1e8e3e;font-weight:600;">No open tickets right now</p></div>';
    return;
  }
  const prioConfig = {
    high:   { bg: 'var(--danger-light)',  fg: 'var(--danger)',  icon: 'ti-alert-circle' },
    medium: { bg: 'var(--warning-light)', fg: 'var(--warning)', icon: 'ti-alert-triangle' },
    low:    { bg: 'var(--info-light)',    fg: 'var(--info)',    icon: 'ti-info-circle' },
  };
  el.innerHTML = '';
  snap.forEach(doc => {
    const t = doc.data();
    const cfg = prioConfig[t.priority] || prioConfig.medium;
    el.innerHTML += `
    <div class="ticket-item">
      <div class="ticket-ico" style="background:${cfg.bg};color:${cfg.fg};">
        <i class="ti ${cfg.icon}"></i>
      </div>
      <div class="ticket-body">
        <div class="ticket-title">${escHtml(t.title || t.message || 'Support request')}</div>
        <div class="ticket-meta">${escHtml(t.userName || 'User')} &middot; ${t.priority||'medium'} priority &middot; ${formatDate(t.createdAt)}</div>
      </div>
      <span class="pill pill-pending" style="flex-shrink:0;font-size:10px;">Open</span>
    </div>`;
  });
}
function renderTicketsTable(tickets) {
  const tbody = document.getElementById('tickets-tbody');
  if (!tickets.length) { tbody.innerHTML = '<tr><td colspan="6" class="loading">No tickets found</td></tr>'; return; }
  tbody.innerHTML = tickets.map(t => {
    const prioClass = t.priority === 'high' ? 'suspended' : t.priority === 'medium' ? 'pending' : 'review';
    const statusClass = t.status === 'open' ? 'pending' : 'active';
    return `<tr>
      <td>${t.id.slice(0,8)}...</td>
      <td>${t.title || t.message || '—'}</td>
      <td>${t.userName || '—'}</td>
      <td><span class="pill pill-${prioClass}">${capitalize(t.priority||'low')}</span></td>
      <td><span class="pill pill-${statusClass}">${capitalize(t.status||'open')}</span></td>
      <td>${formatDate(t.createdAt)}</td>
      <td>${t.status === 'open' ? `<button class="btn btn-approve" onclick="resolveTicket('${t.id}', this)">Resolve</button>` : '—'}</td>
    </tr>`;
  }).join('');
}

async function resolveTicket(id, btn) {
  btn.disabled = true; btn.textContent = '...';
  try {
    await db.collection('support_tickets').doc(id).update({
      status: 'resolved',
      resolvedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast('Ticket resolved!');
  } catch (err) {
    console.error('resolveTicket error:', err);
    showToast('Failed to resolve ticket. Please try again.');
    btn.disabled = false; btn.textContent = 'Resolve';
  }
}

document.getElementById('ticket-filter')?.addEventListener('change', e => {
  const val = e.target.value;
  const filtered = val === 'all' ? allTickets : allTickets.filter(t => t.status === val || t.priority === val);
  renderTicketsTable(filtered);
});

// ============================================
//   REPORTS
// ============================================
function loadReportsList() {
  // Reports are stored in Firebase storage or as metadata in Firestore
  // This shows generated report metadata
  db.collection('reports').orderBy('createdAt', 'desc').limit(10).get().then(snap => {
    const el = document.getElementById('reports-list');
    if (snap.empty) { el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-file-analytics"></i></div><p>No reports generated yet</p></div>'; return; }
    el.innerHTML = snap.docs.map(doc => {
      const r = doc.data();
      return `<div class="user-cell" style="padding:12px 0;border-bottom:1px solid var(--border);">
        <div style="font-size:24px;">
        <div style="flex:1;">
          <div class="user-name">${r.title || 'Report'}</div>
          <div class="user-sub">${r.type || ''} · ${formatDate(r.createdAt)}</div>
        </div>
        ${r.downloadUrl ? `<a href="${r.downloadUrl}" target="_blank" class="btn btn-outline">Download</a>` : ''}
      </div>`;
    }).join('');
  }).catch(() => {});
}

document.getElementById('generate-report-btn')?.addEventListener('click', async () => {
  const type  = document.getElementById('report-type').value;
  const range = document.getElementById('report-range').value;
  showToast(`Generating ${type} report for ${range}...`);
  // Save report request to Firestore — your backend/Cloud Function can process it
  await db.collection('reports').add({
    title: `${type} — ${range}`,
    type, range,
    status: 'generating',
    createdAt: firebase.firestore.FieldValue.serverTimestamp(),
    createdBy: auth.currentUser?.email
  });
  showToast('Report queued! Check back soon.');
  loadReportsList();
});

// ============================================
//   CHARTS (Chart.js)
// ============================================
async function buildRevenueChart() {
  const months = getLast6Months();
  const data = await Promise.all(months.map(async m => {
    const start = new Date(m.year, m.month, 1);
    const end   = new Date(m.year, m.month + 1, 1);
    const snap  = await db.collection('payments').where('createdAt', '>=', start).where('createdAt', '<', end).get();
    let total = 0;
    snap.forEach(d => { total += d.data().amount || 0; });
    return total;
  }));

  const ctx = document.getElementById('revenue-chart');
  if (!ctx) return;
  if (window._revChart) window._revChart.destroy();

  // Premium gradient fill for the chart
  const canvas = ctx;
  const gradient = canvas.getContext ? canvas.getContext('2d').createLinearGradient(0, 0, 0, 220) : null;
  if (gradient) {
    gradient.addColorStop(0, 'rgba(82,37,70,0.85)');
    gradient.addColorStop(1, 'rgba(139,58,107,0.4)');
  }

  window._revChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: months.map(m => m.label),
      datasets: [{
        label: 'Revenue',
        data,
        backgroundColor: gradient || 'rgba(82,37,70,0.8)',
        borderRadius: 8,
        borderSkipped: false,
        hoverBackgroundColor: '#522546',
      }]
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: ctx => ' ₹' + ctx.parsed.y.toLocaleString('en-IN')
          },
          backgroundColor: '#1A0C17',
          titleColor: '#fff',
          bodyColor: 'rgba(255,255,255,0.85)',
          cornerRadius: 8,
          padding: 10,
        }
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: { font: { size: 11, family: 'DM Sans' }, color: '#9E879A' },
          border: { display: false }
        },
        y: {
          ticks: {
            callback: v => '₹' + formatShort(v),
            font: { size: 11, family: 'DM Sans' }, color: '#9E879A'
          },
          grid: { color: 'rgba(228,216,224,0.5)', drawBorder: false },
          border: { display: false }
        }
      },
      animation: { duration: 700, easing: 'easeOutQuart' },
      interaction: { intersect: false, mode: 'index' },
    }
  });
}

function buildPatientChart(patients) {
  const monthly = {};
  patients.forEach(p => {
    if (!p.createdAt) return;
    const d = p.createdAt.toDate ? p.createdAt.toDate() : new Date(p.createdAt);
    const key = d.toLocaleString('default', { month: 'short', year: '2-digit' });
    monthly[key] = (monthly[key] || 0) + 1;
  });
  const labels = Object.keys(monthly).slice(-6);
  const data   = labels.map(l => monthly[l]);
  const ctx = document.getElementById('patient-chart');
  if (!ctx) return;
  if (window._patChart) window._patChart.destroy();
  window._patChart = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [{ label: 'New Patients', data, borderColor: '#1e8e3e', backgroundColor: 'rgba(30,142,62,0.1)', fill: true, tension: 0.4, pointRadius: 4, pointBackgroundColor: '#1e8e3e' }]
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: { x: { grid: { display: false } }, y: { grid: { color: 'rgba(0,0,0,0.05)' } } }
    }
  });
}

function buildRevenueDetailChart(payments) {
  const months = getLast6Months();
  const consultData = [], subscData = [], commData = [];
  months.forEach(m => {
    const mPayments = payments.filter(p => {
      const d = p.createdAt?.toDate ? p.createdAt.toDate() : new Date(p.createdAt || 0);
      return d.getMonth() === m.month && d.getFullYear() === m.year;
    });
    consultData.push(mPayments.filter(p => p.type === 'consultation').reduce((s,p) => s + (p.amount||0), 0));
    subscData.push(mPayments.filter(p => p.type === 'subscription').reduce((s,p) => s + (p.amount||0), 0));
    commData.push(mPayments.filter(p => p.type === 'commission').reduce((s,p) => s + (p.amount||0), 0));
  });
  const ctx = document.getElementById('revenue-detail-chart');
  if (!ctx) return;
  if (window._revDetailChart) window._revDetailChart.destroy();
  window._revDetailChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: months.map(m => m.label),
      datasets: [
        { label: 'Consultations', data: consultData, backgroundColor: '#522546', borderRadius: 4 },
        { label: 'Subscriptions', data: subscData,   backgroundColor: '#1e8e3e', borderRadius: 4 },
        { label: 'Commission',    data: commData,     backgroundColor: '#f29900', borderRadius: 4 }
      ]
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { position: 'top', labels: { font: { size: 11 }, boxWidth: 10 } } },
      scales: {
        x: { stacked: true, grid: { display: false } },
        y: { stacked: true, ticks: { callback: v => '₹' + formatShort(v) }, grid: { color: 'rgba(0,0,0,0.05)' } }
      }
    }
  });
}

function buildMedicinesChart(sorted) {
  const ctx = document.getElementById('medicines-chart');
  if (!ctx) return;
  if (window._medChart) window._medChart.destroy();
  window._medChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: sorted.map(([name]) => name),
      datasets: [{ label: 'Prescriptions', data: sorted.map(([,c]) => c), backgroundColor: '#7b61ff', borderRadius: 6 }]
    },
    options: {
      indexAxis: 'y', responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { grid: { color: 'rgba(0,0,0,0.05)' } },
        y: { grid: { display: false }, ticks: { font: { size: 11 } } }
      }
    }
  });
}

// ============================================
//   BANNERS
// ============================================
let allBanners = [];
let _editingBannerId = null;

async function loadBanners() {
  try {
    const snap = await db.collection('banners').orderBy('createdAt', 'desc').get();
    allBanners = [];
    snap.forEach(doc => allBanners.push({ id: doc.id, ...doc.data() }));
    renderBannersList(allBanners);
    // Update nav badge with active count
    const activeCount = allBanners.filter(b => isBannerActive(b)).length;
    const badge = document.getElementById('nav-banner-count');
    if (activeCount > 0) {
      badge.textContent = activeCount;
      badge.style.display = 'inline';
    } else {
      badge.style.display = 'none';
    }
  } catch (err) {
    console.error('Banner load error:', err);
  }
}

document.getElementById('banner-filter')?.addEventListener('change', e => {
  const val = e.target.value;
  const now = new Date();
  let filtered = allBanners;
  if (val === 'active')    filtered = allBanners.filter(b => isBannerActive(b, now));
  else if (val === 'disabled')   filtered = allBanners.filter(b => !b.isEnabled);
  else if (val === 'scheduled')  filtered = allBanners.filter(b => b.isEnabled && b.startDate && b.startDate.toDate() > now);
  else if (val === 'expired')    filtered = allBanners.filter(b => b.endDate && b.endDate.toDate() < now);
  renderBannersList(filtered);
});

function isBannerActive(b, now = new Date()) {
  if (!b.isEnabled) return false;
  if (b.startDate && b.startDate.toDate() > now) return false;
  if (b.endDate   && b.endDate.toDate()   < now) return false;
  return true;
}

function getBannerStatusBadge(b) {
  const now = new Date();
  if (!b.isEnabled) return '<span class="pill pill-suspended">Disabled</span>';
  if (b.startDate && b.startDate.toDate() > now) return '<span class="pill pill-scheduled">Scheduled</span>';
  if (b.endDate   && b.endDate.toDate()   < now) return '<span class="pill pill-expired">Expired</span>';
  return '<span class="pill pill-active">Active</span>';
}

function renderBannersList(banners) {
  const el = document.getElementById('banners-list');
  if (!banners.length) {
    el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-speakerphone"></i></div><p>No banners yet — create one above.</p></div>';
    return;
  }
  el.innerHTML = banners.map(b => {
    const title = b.title ? escHtml(b.title) : '<em style="color:var(--text-muted)">Untitled Banner</em>';
    const startStr = b.startDate ? formatDate(b.startDate) : null;
    const endStr   = b.endDate   ? formatDate(b.endDate)   : null;
    const dateRange = (startStr || endStr)
      ? `${startStr || 'Anytime'} â†’ ${endStr || 'No end date'}`
      : 'No date restriction';
    const ctaChip = b.ctaText
      ? `<span class="banner-cta-chip">CTA: ${escHtml(b.ctaText)}</span>`
      : '';
    const thumb = b.imageUrl
      ? `<img class="banner-thumb" src="${escHtml(b.imageUrl)}" alt="${escHtml(b.title || 'Banner')}" loading="lazy" />`
      : '<div class="banner-thumb-placeholder"><i class="ti ti-photo"></i></div>';
    return `
    <div class="banner-card" id="banner-card-${b.id}">
      ${thumb}
      <div class="banner-info">
        <div class="banner-name">${title}</div>
        <div class="banner-meta">${dateRange}</div>
        ${ctaChip}
        <div style="margin-top:6px;">${getBannerStatusBadge(b)}</div>
      </div>
      <div class="banner-actions">
        <label class="toggle-label" title="${b.isEnabled ? 'Click to disable' : 'Click to enable'}">
          <input type="checkbox" ${b.isEnabled ? 'checked' : ''} onchange="toggleBanner('${b.id}', this.checked)" />
          <span class="toggle-switch"></span>
        </label>
        <button class="btn btn-outline" onclick="editBanner('${b.id}')" title="Edit banner">
          <i class="ti ti-edit"></i>
        </button>
        <button class="btn btn-reject" onclick="deleteBanner('${b.id}', '${escHtml(b.storagePath||'')}', this)" title="Delete banner">
          <i class="ti ti-trash"></i>
        </button>
      </div>
    </div>`;
  }).join('');
}

async function toggleBanner(id, enabled) {
  try {
    await db.collection('banners').doc(id).update({
      isEnabled: enabled,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    const banner = allBanners.find(b => b.id === id);
    if (banner) banner.isEnabled = enabled;
    showToast(enabled ? 'Banner enabled âœ“' : 'Banner disabled');
    renderBannersList(allBanners);
    loadBanners(); // refresh badge
  } catch (err) {
    showToast('Update failed: ' + err.message);
  }
}

async function deleteBanner(id, storagePath, btn) {
  if (!confirm('Delete this banner? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    await db.collection('banners').doc(id).delete();
    if (storagePath) {
      try { await storage.ref(storagePath).delete(); } catch (_) {} // non-fatal
    }
    showToast('Banner deleted');
    allBanners = allBanners.filter(b => b.id !== id);
    renderBannersList(allBanners);
    loadBanners();
  } catch (err) {
    btn.disabled = false;
    showToast('Delete failed: ' + err.message);
  }
}

function editBanner(id) {
  const banner = allBanners.find(b => b.id === id);
  if (!banner) return;
  _editingBannerId = id;

  document.getElementById('banner-title').value    = banner.title       || '';
  document.getElementById('banner-desc').value     = banner.description || '';
  document.getElementById('banner-cta-text').value = banner.ctaText     || '';
  document.getElementById('banner-cta-url').value  = banner.ctaUrl      || '';
  document.getElementById('banner-enabled').checked = banner.isEnabled;

  if (banner.startDate) {
    const d = banner.startDate.toDate();
    document.getElementById('banner-start-date').value = toLocalDatetimeString(d);
  }
  if (banner.endDate) {
    const d = banner.endDate.toDate();
    document.getElementById('banner-end-date').value = toLocalDatetimeString(d);
  }
  if (banner.imageUrl) {
    const img = document.getElementById('banner-preview-img');
    img.src = banner.imageUrl;
    img.style.display = 'block';
    document.getElementById('banner-upload-placeholder').style.display = 'none';
    document.getElementById('banner-remove-img').style.display = 'flex';
  }

  document.getElementById('banner-form-title').textContent = 'Edit Banner';
  document.getElementById('publish-banner-btn').innerHTML  = '<i class="ti ti-device-floppy"></i> Save Changes';
  document.getElementById('cancel-banner-btn').style.display = 'inline-flex';

  // Scroll to top of form
  document.getElementById('tab-banners').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function cancelBannerEdit() {
  _editingBannerId = null;
  resetBannerForm();
}

function resetBannerForm() {
  _editingBannerId = null;
  document.getElementById('banner-title').value      = '';
  document.getElementById('banner-desc').value       = '';
  document.getElementById('banner-cta-text').value   = '';
  document.getElementById('banner-cta-url').value    = '';
  document.getElementById('banner-start-date').value = '';
  document.getElementById('banner-end-date').value   = '';
  document.getElementById('banner-enabled').checked  = true;
  document.getElementById('banner-file-input').value = '';
  document.getElementById('banner-preview-img').style.display        = 'none';
  document.getElementById('banner-upload-placeholder').style.display = 'block';
  document.getElementById('banner-remove-img').style.display         = 'none';
  document.getElementById('banner-form-title').textContent  = 'Create New Banner';
  document.getElementById('publish-banner-btn').innerHTML   = '<i class="ti ti-upload"></i> Publish Banner';
  document.getElementById('cancel-banner-btn').style.display = 'none';
}

const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const MAX_BANNER_SIZE_MB = 5;

function previewBannerImage(event) {
  const file = event.target.files[0];
  if (!file) return;
  if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
    showToast('Invalid file type. Please upload JPEG, PNG, WebP, or GIF.');
    event.target.value = '';
    return;
  }
  if (file.size > MAX_BANNER_SIZE_MB * 1024 * 1024) {
    showToast(`Image too large — max ${MAX_BANNER_SIZE_MB} MB`);
    event.target.value = '';
    return;
  }
  const reader = new FileReader();
  reader.onload = e => {
    const img = document.getElementById('banner-preview-img');
    img.src = e.target.result;
    img.style.display = 'block';
    document.getElementById('banner-upload-placeholder').style.display = 'none';
    document.getElementById('banner-remove-img').style.display = 'flex';
  };
  reader.readAsDataURL(file);
}

function removeBannerImage(e) {
  e.stopPropagation();
  document.getElementById('banner-file-input').value = '';
  const img = document.getElementById('banner-preview-img');
  img.src = '';
  img.style.display = 'none';
  document.getElementById('banner-upload-placeholder').style.display = 'block';
  document.getElementById('banner-remove-img').style.display = 'none';
}

async function publishBanner() {
  const title      = document.getElementById('banner-title').value.trim();
  const desc       = document.getElementById('banner-desc').value.trim();
  const ctaText    = document.getElementById('banner-cta-text').value.trim();
  const ctaUrl     = document.getElementById('banner-cta-url').value.trim();
  const isEnabled  = document.getElementById('banner-enabled').checked;
  const startVal   = document.getElementById('banner-start-date').value;
  const endVal     = document.getElementById('banner-end-date').value;
  const fileInput  = document.getElementById('banner-file-input');
  const file       = fileInput.files[0];

  const publishBtn  = document.getElementById('publish-banner-btn');
  const progressEl  = document.getElementById('banner-upload-progress');

  if (!_editingBannerId && !file) {
    showToast('Please select a banner image');
    document.getElementById('banner-upload-zone').focus();
    return;
  }
  if (startVal && endVal && new Date(startVal) >= new Date(endVal)) {
    showToast('End date must be after start date');
    return;
  }

  publishBtn.disabled = true;

  let imageUrl    = '';
  let storagePath = '';

  if (_editingBannerId && !file) {
    const existing = allBanners.find(b => b.id === _editingBannerId);
    imageUrl    = existing?.imageUrl    || '';
    storagePath = existing?.storagePath || '';
  }

  if (file) {
    progressEl.style.display = 'flex';
    publishBtn.style.display = 'none';
    const safeName  = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    storagePath     = `banners/${Date.now()}_${safeName}`;
    const fileRef   = storage.ref(storagePath);
    const task      = fileRef.put(file, { contentType: file.type });

    try {
      await new Promise((resolve, reject) => task.on('state_changed', null, reject, resolve));
      imageUrl = await fileRef.getDownloadURL();
    } catch (err) {
      showToast('Upload failed: ' + err.message);
      progressEl.style.display = 'none';
      publishBtn.style.display = 'inline-flex';
      publishBtn.disabled = false;
      return;
    }
    progressEl.style.display = 'none';
    publishBtn.style.display = 'inline-flex';
  }

  const data = {
    title:       title || null,
    description: desc  || null,
    imageUrl,
    storagePath,
    ctaText:  ctaText || null,
    ctaUrl:   ctaUrl  || null,
    isEnabled,
    startDate: startVal ? firebase.firestore.Timestamp.fromDate(new Date(startVal)) : null,
    endDate:   endVal   ? firebase.firestore.Timestamp.fromDate(new Date(endVal))   : null,
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    createdBy: auth.currentUser?.email || 'admin',
  };

  try {
    if (_editingBannerId) {
      await db.collection('banners').doc(_editingBannerId).update(data);
      showToast('Banner updated âœ“');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('banners').add(data);
      showToast('Banner published âœ“');
    }
    resetBannerForm();
    loadBanners();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    publishBtn.disabled = false;
  }
}

// Drag-and-drop support on upload zone
(function setupBannerDragDrop() {
  document.addEventListener('DOMContentLoaded', () => {
    const zone = document.getElementById('banner-upload-zone');
    if (!zone) return;
    zone.addEventListener('dragover',  e => { e.preventDefault(); zone.classList.add('drag-over'); });
    zone.addEventListener('dragleave', () => zone.classList.remove('drag-over'));
    zone.addEventListener('drop', e => {
      e.preventDefault();
      zone.classList.remove('drag-over');
      const file = e.dataTransfer?.files?.[0];
      if (file && file.type.startsWith('image/')) {
        const dt = new DataTransfer();
        dt.items.add(file);
        document.getElementById('banner-file-input').files = dt.files;
        previewBannerImage({ target: { files: dt.files, value: '' } });
      } else {
        showToast('Please drop an image file');
      }
    });
    zone.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        document.getElementById('banner-file-input').click();
      }
    });
  });
})();

// ============================================
//   UTILITIES
// ============================================
function getInitials(name) {
  return name.split(' ').filter(Boolean).map(w => w[0]).join('').slice(0,2).toUpperCase();
}

const avatarColors = [
  { bg: '#F5E6F0', fg: '#522546' }, { bg: '#E8F5E9', fg: '#2E7D32' },
  { bg: '#FFF8E1', fg: '#F57F17' }, { bg: '#FFEBEE', fg: '#C62828' },
  { bg: '#F9EBF5', fg: '#8B3A6B' }, { bg: '#E3F2FD', fg: '#1565C0' }
];
function randomAvatarColor(seed = '') {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) % avatarColors.length;
  return avatarColors[Math.abs(h) % avatarColors.length];
}

function capitalize(str) { return str ? str.charAt(0).toUpperCase() + str.slice(1) : ''; }

function formatCurrency(amount) {
  if (amount >= 10000000) return '₹' + (amount / 10000000).toFixed(1) + 'Cr';
  if (amount >= 100000) return '₹' + (amount / 100000).toFixed(1) + 'L';
  if (amount >= 1000) return '₹' + (amount / 1000).toFixed(1) + 'K';
  return '₹' + Math.round(amount);
}

function formatShort(v) {
  if (v >= 100000) return (v/100000).toFixed(0) + 'L';
  if (v >= 1000)   return (v/1000).toFixed(0) + 'K';
  return v;
}

function formatDate(val) {
  if (!val) return '—';
  const d = val.toDate ? val.toDate() : new Date(val);
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

function getLast6Months() {
  const result = [];
  const now = new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    result.push({ year: d.getFullYear(), month: d.getMonth(), label: d.toLocaleString('default', { month: 'short' }) });
  }
  return result;
}

// ============================================
//   SERVICE REQUESTS — REALTIME LISTENER
// ============================================

let _allRequests         = [];
let _reqTypeFilter       = 'all';
let _requestsUnsubscribe = null;

function initRequestsListener() {
  if (_requestsUnsubscribe) _requestsUnsubscribe();

  _requestsUnsubscribe = db.collection('service_requests')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      _allRequests = [];
      snap.forEach(doc => _allRequests.push({ id: doc.id, ...doc.data() }));
      applyRequestFilters();
      updateRequestStats();
      updateRequestsBadge();
    }, err => console.error('Requests listener error:', err));
}

function updateRequestStats() {
  const counts = { pending: 0, accepted: 0, in_progress: 0, completed: 0, rejected: 0 };
  _allRequests.forEach(r => {
    const s = r.status || 'pending';
    if (s in counts) counts[s]++;
    if (s === 'assigned') counts.accepted++;
  });
  document.getElementById('req-stat-pending').textContent    = counts.pending;
  document.getElementById('req-stat-accepted').textContent   = counts.accepted;
  document.getElementById('req-stat-inprogress').textContent = counts.in_progress;
  document.getElementById('req-stat-completed').textContent  = counts.completed;
  document.getElementById('req-stat-rejected').textContent   = counts.rejected;
}

function updateRequestsBadge() {
  const pending = _allRequests.filter(r => !r.status || r.status === 'pending').length;
  const badge   = document.getElementById('nav-requests-count');
  if (pending > 0) {
    badge.textContent  = pending;
    badge.style.display = 'inline-flex';
  } else {
    badge.style.display = 'none';
  }
}

function filterRequests(type, btn) {
  _reqTypeFilter = type;
  document.querySelectorAll('.req-filter-btn').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  applyRequestFilters();
}

function applyRequestFilters() {
  const statusFilter = document.getElementById('req-status-filter')?.value || 'all';
  const search       = (document.getElementById('req-search')?.value || '').toLowerCase();

  let filtered = _allRequests;

  if (_reqTypeFilter !== 'all') {
    filtered = filtered.filter(r => r.type === _reqTypeFilter);
  }
  if (statusFilter !== 'all') {
    filtered = filtered.filter(r => (r.status || 'pending') === statusFilter);
  }
  if (search) {
    filtered = filtered.filter(r =>
      (r.patientName || '').toLowerCase().includes(search) ||
      (r.patientPhone || '').toLowerCase().includes(search) ||
      (r.serviceName || '').toLowerCase().includes(search)
    );
  }

  const label = document.getElementById('req-count-label');
  if (label) label.textContent = `${filtered.length} request${filtered.length !== 1 ? 's' : ''}`;

  renderRequestsTable(filtered);
}

function renderRequestsTable(requests) {
  const tbody = document.getElementById('requests-tbody');
  if (!tbody) return;

  if (!requests.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="loading">No requests found</td></tr>';
    return;
  }

  tbody.innerHTML = requests.map(r => {
    const status      = r.status || 'pending';
    const typeLabel   = reqTypeLabel(r.type);
    const typeColor   = reqTypeColor(r.type);
    const initials    = getInitials(r.patientName || 'PA');
    const color       = randomAvatarColor(r.patientName);
    const received    = r.createdAt ? formatDate(r.createdAt) : '—';
    const dateTime    = [r.preferredDate, r.preferredTime].filter(Boolean).join(' ') || '—';
    const locData     = r.serviceDetails?.locationData || {};
    const addrText    = locData.formattedAddress || r.address || '—';
    const addrShort   = addrText.length > 35 ? addrText.slice(0, 35) + '…' : addrText;
    const hasGps      = !!(locData.lat && locData.lng);
    const gpsBadge    = hasGps
      ? `<span title="GPS: ${parseFloat(locData.lat).toFixed(5)},${parseFloat(locData.lng).toFixed(5)}" style="display:inline-flex;align-items:center;gap:2px;background:#e8f5e9;color:#2e7d32;font-size:9px;font-weight:700;padding:2px 6px;border-radius:10px;margin-left:4px;vertical-align:middle;">&#x1F4CD; GPS</span>`
      : `<span title="No GPS coordinates" style="display:inline-flex;align-items:center;gap:2px;background:#fff3e0;color:#e65100;font-size:9px;font-weight:700;padding:2px 6px;border-radius:10px;margin-left:4px;vertical-align:middle;">&#x26A0; No GPS</span>`;
    const mapsLink    = hasGps
      ? `<a href="https://www.google.com/maps?q=${locData.lat},${locData.lng}" target="_blank" title="Open in Google Maps" style="margin-left:4px;color:#1a73e8;font-size:12px;">Map</a>`
      : '';
    const address     = `${addrShort}${gpsBadge}${mapsLink}`;
    const isPending   = status === 'pending';
    const isActive    = ['accepted','assigned','in_progress'].includes(status);
    const isDone      = ['completed','cancelled','rejected'].includes(status);

    return `<tr>
      <td>
        <div class="user-cell">
          <div class="doc-avatar" style="background:${color.bg};color:${color.fg};">${initials}</div>
          <div>
            <div class="user-name">${r.patientName || '—'}</div>
            <div class="user-sub">${r.patientPhone || ''}</div>
          </div>
        </div>
      </td>
      <td style="max-width:160px;word-break:break-word;">${r.serviceName || '—'}</td>
      <td><span class="req-type-badge" style="background:${typeColor.bg};color:${typeColor.fg};">${typeLabel}</span></td>
      <td>${dateTime}</td>
      <td style="max-width:140px;font-size:12px;color:var(--text-secondary);">${address}</td>
      <td><span class="pill pill-${statusPillClass(status)}">${capitalize(status.replace('_',' '))}</span></td>
      <td style="font-size:12px;color:var(--text-secondary);">${received}</td>
      <td>
        <div style="display:flex;gap:4px;flex-wrap:wrap;">
          ${isPending ? `
            <button class="btn btn-approve" onclick="updateRequestStatus('${r.id}','accepted',this)">Accept</button>
            <button class="btn btn-reject" onclick="updateRequestStatus('${r.id}','rejected',this)">Reject</button>
          ` : ''}
          ${isActive ? `
            <button class="btn btn-approve" onclick="updateRequestStatus('${r.id}','completed',this)">Complete</button>
            <button class="btn btn-reject" onclick="updateRequestStatus('${r.id}','cancelled',this)">Cancel</button>
          ` : ''}
          <button class="btn btn-outline" onclick="viewRequestDetail('${r.id}')">View</button>
        </div>
      </td>
    </tr>`;
  }).join('');
}

async function updateRequestStatus(id, newStatus, btn) {
  if (btn) { btn.disabled = true; btn.textContent = '…'; }
  try {
    await db.collection('service_requests').doc(id).update({
      status:    newStatus,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast(`Request ${newStatus} âœ“`);
  } catch (err) {
    showToast('Update failed: ' + err.message);
    if (btn) { btn.disabled = false; btn.textContent = capitalize(newStatus); }
  }
}

function viewRequestDetail(id) {
  const r = _allRequests.find(x => x.id === id);
  if (!r) return;

  document.getElementById('req-detail-modal')?.remove();

  const details = r.serviceDetails || {};
  const detailRows = Object.entries(details)
    .filter(([k]) => k !== 'locationData') // shown in dedicated location block
    .map(([k, v]) => `<tr><td style="font-weight:600;font-size:12px;color:var(--text-secondary);padding:5px 0;">${formatDetailKey(k)}</td><td style="font-size:12px;padding:5px 0 5px 12px;">${typeof v === 'object' ? JSON.stringify(v) : v}</td></tr>`)
    .join('');

  const status = r.status || 'pending';

  const modal = document.createElement('div');
  modal.id = 'req-detail-modal';
  modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px;';
  modal.innerHTML = `
    <div style="background:#fff;border-radius:20px;width:100%;max-width:520px;max-height:90vh;overflow-y:auto;padding:28px;">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;">
        <h2 style="font-size:18px;font-weight:700;margin:0;">Request Detail</h2>
        <button onclick="document.getElementById('req-detail-modal').remove()" style="border:none;background:none;font-size:22px;cursor:pointer;color:#666;">&times;</button>
      </div>

      <div style="display:flex;align-items:center;gap:12px;padding:14px;background:#f9f9f9;border-radius:14px;margin-bottom:18px;">
        <div style="width:46px;height:46px;border-radius:50%;background:${reqTypeColor(r.type).bg};display:flex;align-items:center;justify-content:center;font-size:20px;color:${reqTypeColor(r.type).fg};">
          ${reqTypeIcon(r.type)}
        </div>
        <div>
          <div style="font-weight:700;font-size:15px;">${r.serviceName || '—'}</div>
          <div style="font-size:12px;color:#888;">${reqTypeLabel(r.type)} &middot; <span class="pill pill-${statusPillClass(status)}" style="font-size:11px;">${capitalize(status.replace('_',' '))}</span></div>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:18px;">
        <div style="padding:12px;background:#f9f9f9;border-radius:12px;">
          <div style="font-size:11px;font-weight:600;color:#888;margin-bottom:4px;">PATIENT</div>
          <div style="font-weight:600;font-size:14px;">${r.patientName || '—'}</div>
          <div style="font-size:12px;color:#666;">${r.patientPhone || ''}</div>
        </div>
        <div style="padding:12px;background:#f9f9f9;border-radius:12px;">
          <div style="font-size:11px;font-weight:600;color:#888;margin-bottom:4px;">PREFERRED SLOT</div>
          <div style="font-weight:600;font-size:14px;">${r.preferredDate || '—'}</div>
          <div style="font-size:12px;color:#666;">${r.preferredTime || ''}</div>
        </div>
      </div>

      ${buildLocationBlock(r)}

      ${r.notes ? `
      <div style="padding:12px;background:#fffde7;border-radius:12px;margin-bottom:14px;border:1px solid #fff9c4;">
        <div style="font-size:11px;font-weight:600;color:#f9a825;margin-bottom:4px;">NOTES</div>
        <div style="font-size:13px;">${r.notes}</div>
      </div>` : ''}

      ${detailRows ? `
      <div style="margin-bottom:14px;">
        <div style="font-size:12px;font-weight:700;color:var(--text-secondary);margin-bottom:8px;">SERVICE DETAILS</div>
        <table style="width:100%;border-collapse:collapse;">${detailRows}</table>
      </div>` : ''}

      <div style="display:flex;gap:8px;margin-top:20px;flex-wrap:wrap;">
        ${status === 'pending' ? `
          <button class="btn btn-approve" style="flex:1;" onclick="updateRequestStatus('${r.id}','accepted',this);document.getElementById('req-detail-modal').remove();">Accept Request</button>
          <button class="btn btn-reject" onclick="updateRequestStatus('${r.id}','rejected',this);document.getElementById('req-detail-modal').remove();">Reject</button>
        ` : ''}
        ${['accepted','assigned'].includes(status) ? `
          <button class="btn btn-approve" style="flex:1;" onclick="updateRequestStatus('${r.id}','in_progress',this);document.getElementById('req-detail-modal').remove();">Mark In Progress</button>
        ` : ''}
        ${status === 'in_progress' ? `
          <button class="btn btn-approve" style="flex:1;" onclick="updateRequestStatus('${r.id}','completed',this);document.getElementById('req-detail-modal').remove();">Mark Completed</button>
        ` : ''}
        <button class="btn btn-outline" onclick="document.getElementById('req-detail-modal').remove()">Close</button>
      </div>
    </div>`;

  document.body.appendChild(modal);
  modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
}

// Build precise location block for request detail modal
function buildLocationBlock(r) {
  const loc = r.serviceDetails?.locationData || {};
  const formatted = loc.formattedAddress || r.address || '—';
  const lat = loc.lat;
  const lng = loc.lng;

  const hasPrecise = loc.plotNo || loc.building || loc.street || loc.area;

  const mapsUrl = (lat && lng)
    ? `https://www.google.com/maps?q=${lat},${lng}`
    : (formatted !== '—' ? `https://www.google.com/maps/search/${encodeURIComponent(formatted)}` : null);

  const navUrl = (lat && lng)
    ? `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=driving`
    : null;

  const fields = [
    loc.plotNo    ? ['Plot / House', loc.plotNo]        : null,
    loc.building  ? ['Building', loc.building]           : null,
    loc.street    ? ['Street', loc.street]               : null,
    loc.landmark  ? ['Landmark', 'Near ' + loc.landmark] : null,
    loc.area      ? ['Area', loc.area]                   : null,
    loc.city      ? ['City', loc.city]                   : null,
    loc.pincode   ? ['Pincode', loc.pincode]             : null,
    loc.state     ? ['State', loc.state]                 : null,
    (lat && lng)  ? ['Coordinates', `${parseFloat(lat).toFixed(6)}, ${parseFloat(lng).toFixed(6)}`] : null,
  ].filter(Boolean);

  return `
  <div style="padding:14px;background:#f0f7ff;border:1px solid #d0e4ff;border-radius:12px;margin-bottom:14px;">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">
      <div style="font-size:11px;font-weight:700;color:#1a73e8;letter-spacing:0.5px;"> SERVICE LOCATION</div>
      <div style="display:flex;gap:6px;">
        ${navUrl ? `<a href="${navUrl}" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:4px;background:#34a853;color:#fff;font-size:11px;font-weight:700;padding:5px 10px;border-radius:8px;text-decoration:none;">
           Navigate
        </a>` : ''}
        ${mapsUrl ? `<a href="${mapsUrl}" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:4px;background:#1a73e8;color:#fff;font-size:11px;font-weight:700;padding:5px 10px;border-radius:8px;text-decoration:none;">
           Open in Maps
        </a>` : ''}
      </div>
    </div>
    <div style="font-size:13px;font-weight:600;color:#1a1a1a;margin-bottom:${hasPrecise ? '10' : '0'}px;">${formatted}</div>
    ${hasPrecise ? `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:6px;">
      ${fields.map(([k, v]) => `
        <div style="padding:8px 10px;background:#fff;border-radius:8px;border:1px solid #d0e4ff;">
          <div style="font-size:10px;font-weight:700;color:#1a73e8;margin-bottom:2px;">${k.toUpperCase()}</div>
          <div style="font-size:12px;font-weight:600;color:#222;">${v}</div>
        </div>`).join('')}
    </div>` : ''}
  </div>`;
}

function reqTypeLabel(type) {
  const m = { diagnostics: 'Diagnostics', lab_tests: 'Lab Tests', care_assistant: 'Care Assistant', physiotherapy: 'Physiotherapy', equipment: 'Equipment', caregivers: 'Caregivers' };
  return m[type] || capitalize(type || 'Service');
}

function reqTypeColor(type) {
  const m = {
    diagnostics:    { bg: '#e0f7fa', fg: '#0097a7' },
    lab_tests:      { bg: '#e8eaf6', fg: '#3949ab' },
    care_assistant: { bg: '#fff3e0', fg: '#e65100' },
    physiotherapy:  { bg: '#e3f2fd', fg: '#1565c0' },
    equipment:      { bg: '#eceff1', fg: '#37474f' },
    caregivers:     { bg: '#fce4ec', fg: '#c2185b' },
  };
  return m[type] || { bg: '#f3e5f5', fg: '#6a1b9a' };
}

function reqTypeIcon(type) {
  const m = { diagnostics: '', lab_tests: '', care_assistant: '', physiotherapy: '', equipment: '', caregivers: '' };
  return m[type] || '';
}

function statusPillClass(status) {
  const m = { pending: 'pending', accepted: 'active', assigned: 'active', in_progress: 'active', completed: 'success', cancelled: 'inactive', rejected: 'reject' };
  return m[status] || 'pending';
}

function formatDetailKey(k) {
  return k.replace(/([A-Z])/g, ' $1').replace(/_/g, ' ').replace(/^\w/, c => c.toUpperCase());
}

// ============================================
//   NOTIFICATION CENTER
// ============================================

let _notifications       = [];
let _unreadNotifCount    = 0;
let _notifUnsubscribe    = null;
let _seenRequestIds      = new Set(JSON.parse(localStorage.getItem('seenRequests') || '[]'));

function toggleNotifPanel() {
  const panel = document.getElementById('notif-panel');
  if (!panel) return;
  const isVisible = panel.style.display !== 'none';
  panel.style.display = isVisible ? 'none' : 'block';
}

function openRequestFromNotif(id) {
  document.getElementById('notif-panel').style.display = 'none';
  const n = _notifications.find(x => x.id === id);
  if (n) { n._read = true; _seenRequestIds.add(id); }
  localStorage.setItem('seenRequests', JSON.stringify([..._seenRequestIds]));
  _unreadNotifCount = _notifications.filter(x => !x._read).length;
  updateNotifBadge();
  switchTab('requests', 'Service Requests');
  setTimeout(() => viewRequestDetail(id), 200);
}

function timeAgo(ts) {
  const d   = ts.toDate ? ts.toDate() : new Date(ts);
  const sec = Math.floor((Date.now() - d.getTime()) / 1000);
  if (sec < 60)   return 'just now';
  if (sec < 3600) return Math.floor(sec / 60) + 'm ago';
  if (sec < 86400) return Math.floor(sec / 3600) + 'h ago';
  return Math.floor(sec / 86400) + 'd ago';
}

// Close notif panel when clicking outside
document.addEventListener('click', e => {
  const wrapper = document.getElementById('notif-wrapper');
  if (wrapper && !wrapper.contains(e.target)) {
    const panel = document.getElementById('notif-panel');
    if (panel) panel.style.display = 'none';
  }
});

function toLocalDatetimeString(date) {
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

// ============================================
//   HOSPITALS
// ============================================
let allHospitals = [];
let _editingHospitalId = null;
let _hospitalsListener = null;

function loadHospitals() {
  if (_hospitalsListener) _hospitalsListener();
  _hospitalsListener = db.collection('hospitals')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      allHospitals = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      filterHospitals();
      const enabledCount = allHospitals.filter(h => h.isEnabled).length;
      const badge = document.getElementById('nav-hospital-count');
      if (badge) {
        if (enabledCount > 0) { badge.textContent = enabledCount; badge.style.display = 'inline'; }
        else badge.style.display = 'none';
      }
    }, err => console.error('Hospitals load error:', err));
}

function filterHospitals() {
  const q      = (document.getElementById('hospital-search')?.value || '').toLowerCase();
  const filter = document.getElementById('hospital-type-filter')?.value || 'all';
  let filtered = allHospitals;
  if (q) filtered = filtered.filter(h =>
    (h.name || '').toLowerCase().includes(q) ||
    (h.address || '').toLowerCase().includes(q)
  );
  if (filter === 'emergency') filtered = filtered.filter(h => h.isEmergency);
  else if (filter === 'enabled')   filtered = filtered.filter(h => h.isEnabled);
  else if (filter === 'disabled')  filtered = filtered.filter(h => !h.isEnabled);
  renderHospitalsList(filtered);
}

function renderHospitalsList(hospitals) {
  const el = document.getElementById('hospitals-list');
  if (!el) return;
  if (!hospitals.length) {
    el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-building-hospital"></i></div><p>No hospitals added yet</p></div>';
    return;
  }
  el.innerHTML = hospitals.map(h => `
    <div class="banner-card" id="hospital-card-${h.id}">
      <div class="banner-thumb-placeholder" style="background:#F5E6F0;color:#522546;font-size:26px;">
        <i class="ti ti-building-hospital"></i>
      </div>
      <div class="banner-info">
        <div class="banner-name">${escHtml(h.name || '—')}</div>
        <div class="banner-meta">${escHtml(h.address || '—')}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px;">
          ${h.phone ? `<span class="banner-cta-chip"><i class="ti ti-phone" style="font-size:11px;"></i> ${escHtml(h.phone)}</span>` : ''}
          ${h.isEmergency ? '<span class="pill pill-suspended"> Emergency</span>' : ''}
          ${h.isEnabled ? '<span class="pill pill-active">Enabled</span>' : '<span class="pill pill-suspended">Disabled</span>'}
        </div>
      </div>
      <div class="banner-actions">
        <label class="toggle-label" title="${h.isEnabled ? 'Click to disable' : 'Click to enable'}">
          <input type="checkbox" ${h.isEnabled ? 'checked' : ''} onchange="toggleHospital('${h.id}', this.checked)" />
          <span class="toggle-switch"></span>
        </label>
        <button class="btn btn-outline" onclick="editHospital('${h.id}')" title="Edit">
          <i class="ti ti-edit"></i>
        </button>
        <button class="btn btn-reject" onclick="deleteHospital('${h.id}', this)" title="Delete">
          <i class="ti ti-trash"></i>
        </button>
      </div>
    </div>`).join('');
}

async function saveHospital() {
  const name      = document.getElementById('hosp-name')?.value.trim();
  const address   = document.getElementById('hosp-address')?.value.trim();
  const phone     = document.getElementById('hosp-phone')?.value.trim();
  const mapsUrl   = document.getElementById('hosp-maps')?.value.trim();
  const isEmergency = document.getElementById('hosp-emergency')?.checked || false;
  const isEnabled   = document.getElementById('hosp-enabled')?.checked !== false;

  if (!name || !address) {
    showToast('Hospital name and address are required');
    return;
  }

  const btn = document.getElementById('save-hospital-btn');
  btn.disabled = true;
  btn.textContent = 'Saving…';

  const data = {
    name, address,
    phone:     phone   || '',
    mapsUrl:   mapsUrl || '',
    isEmergency,
    isEnabled,
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  };

  try {
    if (_editingHospitalId) {
      await db.collection('hospitals').doc(_editingHospitalId).update(data);
      showToast('Hospital updated âœ“');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('hospitals').add(data);
      showToast('Hospital added âœ“');
    }
    cancelHospitalEdit();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class="ti ti-device-floppy"></i> Save Hospital';
  }
}

function editHospital(id) {
  const h = allHospitals.find(x => x.id === id);
  if (!h) return;
  _editingHospitalId = id;
  document.getElementById('hosp-name').value    = h.name    || '';
  document.getElementById('hosp-address').value = h.address || '';
  document.getElementById('hosp-phone').value   = h.phone   || '';
  document.getElementById('hosp-maps').value    = h.mapsUrl || '';
  document.getElementById('hosp-emergency').checked = h.isEmergency || false;
  document.getElementById('hosp-enabled').checked   = h.isEnabled !== false;
  document.getElementById('hospital-form-title').textContent   = 'Edit Hospital';
  document.getElementById('save-hospital-btn').innerHTML = '<i class="ti ti-device-floppy"></i> Save Changes';
  document.getElementById('cancel-hospital-btn').style.display = 'inline-flex';
  document.getElementById('tab-hospitals').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function cancelHospitalEdit() {
  _editingHospitalId = null;
  ['hosp-name','hosp-address','hosp-phone','hosp-maps'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  const emEl = document.getElementById('hosp-emergency');
  if (emEl) emEl.checked = false;
  const enEl = document.getElementById('hosp-enabled');
  if (enEl) enEl.checked = true;
  document.getElementById('hospital-form-title').textContent   = 'Add Hospital';
  document.getElementById('save-hospital-btn').innerHTML = '<i class="ti ti-device-floppy"></i> Save Hospital';
  document.getElementById('cancel-hospital-btn').style.display = 'none';
}

async function toggleHospital(id, enabled) {
  try {
    await db.collection('hospitals').doc(id).update({
      isEnabled: enabled,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast(enabled ? 'Hospital enabled âœ“' : 'Hospital disabled');
  } catch (err) {
    showToast('Update failed: ' + err.message);
  }
}

async function deleteHospital(id, btn) {
  if (!confirm('Delete this hospital? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    await db.collection('hospitals').doc(id).delete();
    showToast('Hospital deleted');
  } catch (err) {
    btn.disabled = false;
    showToast('Delete failed: ' + err.message);
  }
}

// ============================================
//   AMBULANCES
// ============================================
let allAmbulances = [];
let _editingAmbulanceId = null;
let _ambulancesListener = null;

function loadAmbulances() {
  if (_ambulancesListener) _ambulancesListener();
  _ambulancesListener = db.collection('ambulances')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      allAmbulances = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      filterAmbulances();
      const enabledCount = allAmbulances.filter(a => a.isEnabled).length;
      const badge = document.getElementById('nav-ambulance-count');
      if (badge) {
        if (enabledCount > 0) { badge.textContent = enabledCount; badge.style.display = 'inline'; }
        else badge.style.display = 'none';
      }
    }, err => console.error('Ambulances load error:', err));
}

function filterAmbulances() {
  const filter = document.getElementById('ambulance-type-filter')?.value || 'all';
  const filtered = filter === 'all' ? allAmbulances : allAmbulances.filter(a => a.type === filter);
  renderAmbulancesList(filtered);
}

function renderAmbulancesList(ambulances) {
  const el = document.getElementById('ambulances-list');
  if (!el) return;
  if (!ambulances.length) {
    el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-ambulance"></i></div><p>No ambulance services added yet</p></div>';
    return;
  }
  const typeColors = { Basic: '#d93025', ALS: '#e65100', ICU: '#4a148c' };
  el.innerHTML = ambulances.map(a => {
    const tc = typeColors[a.type] || '#d93025';
    return `
    <div class="banner-card" id="ambulance-card-${a.id}">
      <div class="banner-thumb-placeholder" style="background:${tc}18;color:${tc};font-size:26px;">
        <i class="ti ti-ambulance"></i>
      </div>
      <div class="banner-info">
        <div class="banner-name">${escHtml(a.name || '—')}</div>
        <div class="banner-meta">${escHtml(a.serviceArea || '—')}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px;">
          <span class="pill" style="background:${tc}18;color:${tc};border:1px solid ${tc}44;">${escHtml(a.type || 'Basic')}</span>
          ${a.phone ? `<span class="banner-cta-chip"><i class="ti ti-phone" style="font-size:11px;"></i> ${escHtml(a.phone)}</span>` : ''}
          ${(a.latitude && a.longitude) ? `<span class="banner-cta-chip"><i class="ti ti-map-pin" style="font-size:11px;"></i> ${a.latitude.toFixed(4)}, ${a.longitude.toFixed(4)}</span>` : '<span class="pill pill-pending">No location set</span>'}
          ${a.isAvailable ? '<span class="pill pill-active">Available</span>' : '<span class="pill pill-pending">Busy</span>'}
          ${a.isEnabled ? '' : '<span class="pill pill-suspended">Disabled</span>'}
        </div>
      </div>
      <div class="banner-actions">
        <label class="toggle-label" title="${a.isEnabled ? 'Click to disable' : 'Click to enable'}">
          <input type="checkbox" ${a.isEnabled ? 'checked' : ''} onchange="toggleAmbulance('${a.id}', this.checked)" />
          <span class="toggle-switch"></span>
        </label>
        <button class="btn btn-outline" onclick="editAmbulance('${a.id}')" title="Edit">
          <i class="ti ti-edit"></i>
        </button>
        <button class="btn btn-reject" onclick="deleteAmbulance('${a.id}', this)" title="Delete">
          <i class="ti ti-trash"></i>
        </button>
      </div>
    </div>`;
  }).join('');
}

async function saveAmbulance() {
  const name        = document.getElementById('amb-name')?.value.trim();
  const phone       = document.getElementById('amb-phone')?.value.trim();
  const type        = document.getElementById('amb-type')?.value || 'Basic';
  const serviceArea = document.getElementById('amb-area')?.value.trim();
  const latRaw      = document.getElementById('amb-lat')?.value.trim();
  const lngRaw      = document.getElementById('amb-lng')?.value.trim();
  const isAvailable = document.getElementById('amb-available')?.checked !== false;
  const isEnabled   = document.getElementById('amb-enabled')?.checked !== false;

  if (!name || !phone) {
    showToast('Service name and phone are required');
    return;
  }

  const latitude  = latRaw !== '' ? parseFloat(latRaw) : null;
  const longitude = lngRaw !== '' ? parseFloat(lngRaw) : null;
  if ((latRaw !== '' && Number.isNaN(latitude)) || (lngRaw !== '' && Number.isNaN(longitude))) {
    showToast('Latitude/longitude must be valid numbers');
    return;
  }

  const btn = document.getElementById('save-ambulance-btn');
  btn.disabled = true;
  btn.textContent = 'Saving…';

  const data = {
    name, phone, type,
    serviceArea: serviceArea || '',
    latitude: latitude ?? null,
    longitude: longitude ?? null,
    isAvailable,
    isEnabled,
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  };

  try {
    if (_editingAmbulanceId) {
      await db.collection('ambulances').doc(_editingAmbulanceId).update(data);
      showToast('Ambulance service updated âœ“');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('ambulances').add(data);
      showToast('Ambulance service added âœ“');
    }
    cancelAmbulanceEdit();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class="ti ti-device-floppy"></i> Save Ambulance';
  }
}

function editAmbulance(id) {
  const a = allAmbulances.find(x => x.id === id);
  if (!a) return;
  _editingAmbulanceId = id;
  document.getElementById('amb-name').value  = a.name        || '';
  document.getElementById('amb-phone').value = a.phone       || '';
  document.getElementById('amb-type').value  = a.type        || 'Basic';
  document.getElementById('amb-area').value  = a.serviceArea || '';
  document.getElementById('amb-lat').value   = a.latitude ?? '';
  document.getElementById('amb-lng').value   = a.longitude ?? '';
  document.getElementById('amb-available').checked = a.isAvailable !== false;
  document.getElementById('amb-enabled').checked   = a.isEnabled   !== false;
  document.getElementById('ambulance-form-title').textContent   = 'Edit Ambulance Service';
  document.getElementById('save-ambulance-btn').innerHTML = '<i class="ti ti-device-floppy"></i> Save Changes';
  document.getElementById('cancel-ambulance-btn').style.display = 'inline-flex';
  document.getElementById('tab-ambulances').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function cancelAmbulanceEdit() {
  _editingAmbulanceId = null;
  ['amb-name','amb-phone','amb-area','amb-lat','amb-lng'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  const typeEl = document.getElementById('amb-type');
  if (typeEl) typeEl.value = 'Basic';
  const avEl = document.getElementById('amb-available');
  if (avEl) avEl.checked = true;
  const enEl = document.getElementById('amb-enabled');
  if (enEl) enEl.checked = true;
  document.getElementById('ambulance-form-title').textContent   = 'Add Ambulance Service';
  document.getElementById('save-ambulance-btn').innerHTML = '<i class="ti ti-device-floppy"></i> Save Ambulance';
  document.getElementById('cancel-ambulance-btn').style.display = 'none';
}

async function toggleAmbulance(id, enabled) {
  try {
    await db.collection('ambulances').doc(id).update({
      isEnabled: enabled,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast(enabled ? 'Ambulance service enabled âœ“' : 'Ambulance service disabled');
  } catch (err) {
    showToast('Update failed: ' + err.message);
  }
}

async function deleteAmbulance(id, btn) {
  if (!confirm('Delete this ambulance service? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    await db.collection('ambulances').doc(id).delete();
    showToast('Ambulance service deleted');
  } catch (err) {
    btn.disabled = false;
    showToast('Delete failed: ' + err.message);
  }
}

// ============================================
//   REFERRALS  (realtime, with fraud controls)
// ============================================

let _allReferrals      = [];
let _referralUnsub     = null;
let _refSettingsUnsub  = null;

// ── Realtime config listener ─────────────────────────────
function initReferralSettingsListener() {
  if (_refSettingsUnsub) _refSettingsUnsub();
  _refSettingsUnsub = db.collection('referralConfig').doc('settings')
    .onSnapshot(snap => {
      const d = snap.exists ? snap.data() : {};
      const set = (id, val) => { const el = document.getElementById(id); if (el) el[el.type === 'checkbox' ? 'checked' : 'value'] = val ?? el.defaultValue ?? ''; };
      set('ref-enabled',          d.referralEnabled !== false);
      set('ref-rewards-enabled',  d.rewardsEnabled  !== false);
      set('ref-referrer-reward',  d.referrerReward  ?? 50);
      set('ref-referred-reward',  d.referredReward  ?? 25);
      set('ref-trigger',          d.rewardTriggerCondition ?? 'on_signup');
      set('ref-max-limit',        d.maxReferralLimit ?? 0);
      set('ref-campaign-title',   d.campaignTitle   ?? 'Refer & Earn');
      set('ref-campaign-message', d.campaignMessage ?? '');
      set('ref-banner-text',      d.bannerText      ?? '');
      if (d.offerExpiryDate) {
        const dt  = d.offerExpiryDate.toDate ? d.offerExpiryDate.toDate() : new Date(d.offerExpiryDate);
        const el  = document.getElementById('ref-expiry-date');
        if (el) el.value = dt.toISOString().slice(0, 16);
      }
    }, err => console.error('referralConfig listener error', err));
}

// Keep legacy name so existing callers still work
function loadReferralSettings() { initReferralSettingsListener(); }

// ── Save settings ────────────────────────────────────────
async function saveReferralSettings() {
  const btn    = document.getElementById('save-referral-btn');
  const status = document.getElementById('ref-save-status');
  btn.disabled = true;
  btn.innerHTML = '<i class=”ti ti-loader”></i> Saving…';
  if (status) status.textContent = '';

  const referrerReward = parseFloat(document.getElementById('ref-referrer-reward').value) || 0;
  const referredReward = parseFloat(document.getElementById('ref-referred-reward').value) || 0;

  if (referrerReward < 0 || referredReward < 0) {
    showToast('Reward amounts must be non-negative.');
    btn.disabled = false;
    btn.innerHTML = '<i class=”ti ti-device-floppy”></i> Save Settings';
    return;
  }

  const expiryRaw  = document.getElementById('ref-expiry-date').value;
  const expiryDate = expiryRaw ? firebase.firestore.Timestamp.fromDate(new Date(expiryRaw)) : null;

  const payload = {
    referralEnabled:        document.getElementById('ref-enabled').checked,
    rewardsEnabled:         document.getElementById('ref-rewards-enabled').checked,
    referrerReward,
    referredReward,
    rewardTriggerCondition: document.getElementById('ref-trigger').value,
    maxReferralLimit:       parseInt(document.getElementById('ref-max-limit').value) || 0,
    campaignTitle:          document.getElementById('ref-campaign-title').value.trim(),
    campaignMessage:        document.getElementById('ref-campaign-message').value.trim(),
    bannerText:             document.getElementById('ref-banner-text').value.trim(),
    offerExpiryDate:        expiryDate,
    updatedAt:              firebase.firestore.FieldValue.serverTimestamp(),
    updatedBy:              auth.currentUser?.email || 'admin',
  };

  try {
    await db.collection('referralConfig').doc('settings').set(payload, { merge: true });
    if (status) status.textContent = '✓ Saved ' + new Date().toLocaleTimeString();
    showToast('Referral settings saved ✓');
  } catch (err) {
    showToast('Save failed: ' + escHtml(err.message));
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class=”ti ti-device-floppy”></i> Save Settings';
  }
}

// ── Realtime referrals listener ───────────────────────────
function initReferralsListener() {
  if (_referralUnsub) _referralUnsub();
  document.getElementById('referrals-tbody').innerHTML =
    '<tr><td colspan=”8” class=”loading”>Loading referrals…</td></tr>';

  _referralUnsub = db.collection('referrals')
    .orderBy('createdAt', 'desc')
    .limit(300)
    .onSnapshot(snap => {
      _allReferrals = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      _updateReferralStats(_allReferrals);
      _renderTopReferrers(_allReferrals);
      filterReferrals();
    }, err => {
      document.getElementById('referrals-tbody').innerHTML =
        `<tr><td colspan=”8” style=”text-align:center;color:var(--danger);”>Failed: ${escHtml(err.message)}</td></tr>`;
    });
}

// Keep legacy names so init block still works
function loadReferralStats() {}
function loadReferrals()     { initReferralsListener(); }

// ── Stats update ─────────────────────────────────────────
function _updateReferralStats(list) {
  let total = 0, rewarded = 0, pending = 0, fraud = 0, totalRewards = 0;
  list.forEach(r => {
    total++;
    if      (r.status === 'rewarded') { rewarded++; totalRewards += (r.referrerRewardAmount||0)+(r.referredRewardAmount||0); }
    else if (r.status === 'pending')  { pending++; }
    else if (r.status === 'fraud')    { fraud++; }
  });
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  set('ref-stat-total',    total.toLocaleString());
  set('ref-stat-rewarded', rewarded.toLocaleString());
  set('ref-stat-pending',  pending.toLocaleString());
  set('ref-stat-rewards',  '₹' + totalRewards.toLocaleString('en-IN'));
  const fraudEl = document.getElementById('ref-stat-fraud');
  if (fraudEl) fraudEl.textContent = fraud.toLocaleString();
}

// ── Top referrers leaderboard ────────────────────────────
function _renderTopReferrers(list) {
  const tbody = document.getElementById('ref-top-tbody');
  if (!tbody) return;

  // Aggregate by referrer
  const map = {};
  list.forEach(r => {
    if (r.status === 'fraud') return;
    const key  = r.referrerId || '—';
    const name = r.referrerName || ('User …' + key.slice(-4));
    if (!map[key]) map[key] = { name, code: r.referralCode || '—', total: 0, rewarded: 0, earned: 0 };
    map[key].total++;
    if (r.status === 'rewarded') { map[key].rewarded++; map[key].earned += r.referrerRewardAmount || 0; }
  });

  const sorted = Object.values(map).sort((a, b) => b.earned - a.earned).slice(0, 10);
  if (!sorted.length) {
    tbody.innerHTML = '<tr><td colspan=”5” style=”text-align:center;color:var(--text-muted);”>No data yet.</td></tr>';
    return;
  }
  tbody.innerHTML = sorted.map((u, i) => `
    <tr>
      <td><span style=”font-weight:700;color:var(--primary)”>#${i+1}</span></td>
      <td>${escHtml(u.name)}</td>
      <td><code>${escHtml(u.code)}</code></td>
      <td>${u.rewarded} / ${u.total}</td>
      <td style=”font-weight:700;color:var(--success)”>₹${u.earned.toLocaleString('en-IN')}</td>
    </tr>`).join('');
}

// ── Filter & render referral history ─────────────────────
function filterReferrals() {
  const filter = (document.getElementById('ref-filter')?.value  || 'all');
  const search = (document.getElementById('ref-search')?.value  || '').toLowerCase().trim();

  let filtered = filter === 'all' ? [..._allReferrals] : _allReferrals.filter(r => r.status === filter);
  if (search) {
    filtered = filtered.filter(r =>
      (r.referrerName     || '').toLowerCase().includes(search) ||
      (r.referralCode     || '').toLowerCase().includes(search) ||
      (r.referrerId       || '').toLowerCase().includes(search) ||
      (r.referredUserId   || '').toLowerCase().includes(search)
    );
  }
  renderReferrals(filtered);
}

function renderReferrals(list) {
  const tbody = document.getElementById('referrals-tbody');
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan=”8” style=”text-align:center;color:var(--text-muted);”>No referrals found.</td></tr>';
    return;
  }
  tbody.innerHTML = list.map(r => {
    const date = r.createdAt?.toDate
      ? r.createdAt.toDate().toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })
      : '—';
    const statusBadge = r.status === 'rewarded'
      ? '<span class=”badge badge-green”>Rewarded</span>'
      : r.status === 'fraud'
      ? '<span class=”badge badge-red”>Fraud</span>'
      : '<span class=”badge badge-yellow”>Pending</span>';
    const fraudBtn = r.status !== 'fraud'
      ? `<button class=”btn-sm btn-danger” onclick=”markReferralFraud('${r.id}')” title=”Mark as fraud”></button>`
      : `<button class=”btn-sm btn-secondary” onclick=”unmarkReferralFraud('${r.id}')” title=”Restore”>↩</button>`;
    const rewardBtn = r.status === 'pending'
      ? `<button class=”btn-sm btn-primary” onclick=”manuallyRewardReferral('${r.id}')” title=”Manually reward”></button>`
      : '';
    return `<tr>
      <td>${escHtml(r.referrerName || r.referrerId?.slice(0,8) || '—')}</td>
      <td>${escHtml(r.referredUserId?.slice(0,8) || '—')}</td>
      <td><code>${escHtml(r.referralCode || '—')}</code></td>
      <td>₹${(r.referrerRewardAmount || 0).toLocaleString('en-IN')}</td>
      <td>₹${(r.referredRewardAmount || 0).toLocaleString('en-IN')}</td>
      <td>${statusBadge}</td>
      <td>${date}</td>
      <td style=”white-space:nowrap”>${fraudBtn} ${rewardBtn}</td>
    </tr>`;
  }).join('');
}

// ── Fraud management ──────────────────────────────────────
async function markReferralFraud(referralId) {
  if (!confirm('Mark this referral as fraud? This will flag it for review.')) return;
  try {
    await db.collection('referrals').doc(referralId).update({
      status:    'fraud',
      flaggedAt: firebase.firestore.FieldValue.serverTimestamp(),
      flaggedBy: auth.currentUser?.email || 'admin',
    });
    showToast('Referral flagged as fraud.');
  } catch (err) {
    showToast('Error: ' + escHtml(err.message));
  }
}

async function unmarkReferralFraud(referralId) {
  try {
    await db.collection('referrals').doc(referralId).update({ status: 'pending', flaggedAt: null });
    showToast('Referral restored to pending.');
  } catch (err) {
    showToast('Error: ' + escHtml(err.message));
  }
}

// ── Manual reward trigger (admin) ─────────────────────────
async function manuallyRewardReferral(referralId) {
  if (!confirm('Manually credit rewards for this referral now?')) return;
  try {
    const snap = await db.collection('referrals').doc(referralId).get();
    if (!snap.exists) { showToast('Referral not found.'); return; }
    const r = snap.data();
    if (r.status !== 'pending') { showToast('Referral is not pending.'); return; }

    const batch = db.batch();

    // Credit referrer
    if ((r.referrerRewardAmount || 0) > 0 && r.referrerId) {
      const refRef = db.collection('users').doc(r.referrerId);
      batch.update(refRef, {
        walletBalance:  firebase.firestore.FieldValue.increment(r.referrerRewardAmount),
        referralPoints: firebase.firestore.FieldValue.increment(1),
      });
      batch.set(refRef.collection('transactions').doc(), {
        title: 'Referral Bonus (Admin)', amount: r.referrerRewardAmount,
        type: 'credit', category: 'referral',
        description: 'Manually credited by admin',
        timestamp: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Credit referred user
    if ((r.referredRewardAmount || 0) > 0 && r.referredUserId) {
      const newRef = db.collection('users').doc(r.referredUserId);
      batch.update(newRef, { walletBalance: firebase.firestore.FieldValue.increment(r.referredRewardAmount) });
      batch.set(newRef.collection('transactions').doc(), {
        title: 'Welcome Bonus (Admin)', amount: r.referredRewardAmount,
        type: 'credit', category: 'referral',
        description: 'Manually credited by admin',
        timestamp: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Update referral record
    batch.update(db.collection('referrals').doc(referralId), {
      status:     'rewarded',
      rewardedAt: firebase.firestore.FieldValue.serverTimestamp(),
      rewardedBy: auth.currentUser?.email || 'admin',
    });

    await batch.commit();
    showToast('Rewards credited successfully ✓');
  } catch (err) {
    showToast('Error: ' + escHtml(err.message));
  }
}

// ============================================
//   PATIENT FEEDBACK
// ============================================
let allFeedbacks = [];

async function loadFeedbacks() {
  try {
    const snap = await db.collection('feedbacks').orderBy('createdAt', 'desc').get();
    allFeedbacks = [];
    snap.forEach(doc => allFeedbacks.push({ id: doc.id, ...doc.data() }));

    // Summary stats
    const total     = allFeedbacks.length;
    const immediate = allFeedbacks.filter(f => f.type === 'immediate').length;
    const followup  = allFeedbacks.filter(f => f.type === 'followup').length;
    const ratings   = allFeedbacks.map(f => f.rating || 0).filter(r => r > 0);
    const avg       = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : '—';

    document.getElementById('fb-avg-rating').textContent  = avg === '—' ? '—' : `${avg} â­`;
    document.getElementById('fb-total').textContent       = total.toLocaleString();
    document.getElementById('fb-immediate').textContent   = immediate.toLocaleString();
    document.getElementById('fb-followup').textContent    = followup.toLocaleString();

    // Update sidebar badge
    if (total > 0) {
      const badge = document.getElementById('nav-feedback-count');
      badge.textContent = total;
      badge.style.display = 'inline-flex';
    }

    renderFeedbackTable(allFeedbacks);
  } catch (err) {
    console.error('Feedback load error:', err);
  }
}

function filterFeedback() {
  const type   = document.getElementById('fb-type-filter').value;
  const rating = document.getElementById('fb-rating-filter').value;
  const q      = (document.getElementById('fb-search').value || '').toLowerCase();

  let list = [...allFeedbacks];

  if (type !== 'all')   list = list.filter(f => f.type === type);
  if (rating !== 'all') list = list.filter(f => (f.rating || 0) === parseInt(rating));
  if (q) list = list.filter(f =>
    (f.patientName || '').toLowerCase().includes(q) ||
    (f.doctorName  || '').toLowerCase().includes(q) ||
    (f.comment     || '').toLowerCase().includes(q)
  );

  renderFeedbackTable(list);
}

function renderFeedbackTable(list) {
  const tbody = document.getElementById('feedback-tbody');
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="loading">No feedback found</td></tr>';
    return;
  }

  tbody.innerHTML = list.map(f => {
    // Stars HTML
    const stars = Array.from({ length: 5 }, (_, i) =>
      `<span style="color:${i < (f.rating || 0) ? '#ffa000' : '#ddd'};font-size:13px;">&#9733;</span>`
    ).join('');

    // Feeling badge color
    const feelingColor = {
      'Much Better': '#2e7d32', 'Better': '#66bb6a',
      'Same': '#e65100',        'Worse':  '#b71c1c',
    }[f.feeling] || '#888';
    const feelingHtml = f.feeling
      ? `<span style="background:${feelingColor}20;color:${feelingColor};padding:3px 8px;border-radius:8px;font-size:11px;font-weight:700;">${f.feeling}</span>`
      : '—';

    // Type badge
    const typeHtml = f.type === 'immediate'
      ? '<span class="pill" style="background:#e3f2fd;color:#1565c0;">Immediate</span>'
      : '<span class="pill" style="background:#f3e5f5;color:#7b1fa2;">Follow-up</span>';

    const date = f.createdAt
      ? f.createdAt.toDate().toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })
      : '—';

    const comment = f.comment
      ? `<span title="${f.comment.replace(/"/g, '&quot;')}" style="cursor:help;">${f.comment.length > 35 ? f.comment.slice(0, 35) + '…' : f.comment}</span>`
      : '<span style="color:#aaa;">—</span>';

    return `<tr>
      <td><div class="user-name">${f.patientName || '—'}</div></td>
      <td><div class="user-sub">${f.doctorName || '—'}</div></td>
      <td>${typeHtml}</td>
      <td>${f.rating > 0 ? stars : '<span style="color:#aaa;">No rating</span>'}</td>
      <td>${feelingHtml}</td>
      <td>${f.painLevel > 0 ? `<b>${f.painLevel}</b>/10` : '0/10'}</td>
      <td style="max-width:200px;">${comment}</td>
      <td style="white-space:nowrap;">${date}</td>
    </tr>`;
  }).join('');
}

// ============================================
//   MOBILE SIDEBAR TOGGLE
// ============================================

function toggleSidebar() {
  const sidebar  = document.getElementById('sidebar');
  const overlay  = document.getElementById('sidebar-overlay');
  const isOpen   = sidebar.classList.contains('open');
  if (isOpen) {
    sidebar.classList.remove('open');
    overlay.classList.remove('active');
  } else {
    sidebar.classList.add('open');
    overlay.classList.add('active');
  }
}

function closeSidebar() {
  document.getElementById('sidebar').classList.remove('open');
  document.getElementById('sidebar-overlay').classList.remove('active');
}

// Close sidebar on tab nav click (mobile)
document.querySelectorAll('.nav-item[data-tab]').forEach(item => {
  item.addEventListener('click', () => {
    if (window.innerWidth <= 768) closeSidebar();
  });
});

// ============================================
//   REALTIME OVERVIEW — replace static .get()
// ============================================

let _overviewUnsubscribes = [];

function initOverviewRealtime() {
  _overviewUnsubscribes.forEach(u => u && u());
  _overviewUnsubscribes = [];

  // Doctors count — realtime
  _overviewUnsubscribes.push(
    db.collection('doctors').onSnapshot(snap => {
      const el = document.getElementById('stat-doctors');
      if (el) { el.textContent = snap.size.toLocaleString(); el.classList.add('stat-updated'); setTimeout(() => el.classList.remove('stat-updated'), 500); }
      // Pending list
      const pendingDocs = snap.docs.filter(d => { const s = d.data().status; return !s || s === 'pending'; }).slice(0, 5);
      renderPendingList(pendingDocs);
      // Notify new doctors
      snap.docChanges().forEach(change => {
        if (change.type === 'added') {
          const d = change.doc.data();
          if (!d.status || d.status === 'pending') {
            addSystemNotif('doctor_reg', { id: change.doc.id, name: d.name || 'New doctor', specialty: d.specialty || d.specialisation || d.specialization || '' });
          }
        }
      });
    }, err => console.error('doctors listener', err))
  );

  // Patients count — realtime
  _overviewUnsubscribes.push(
    db.collection('users').onSnapshot(snap => {
      const el = document.getElementById('stat-patients');
      if (el) { el.textContent = snap.size.toLocaleString(); el.classList.add('stat-updated'); setTimeout(() => el.classList.remove('stat-updated'), 500); }
    }, err => console.error('users listener', err))
  );

  // Revenue this month -- realtime
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  _overviewUnsubscribes.push(
    db.collection('payments').where('createdAt', '>=', startOfMonth).onSnapshot(snap => {
      let total = 0;
      snap.forEach(d => {
        const pd = d.data();
        if (!pd.status || pd.status === 'completed' || pd.status === 'success' || pd.status === 'paid') {
          total += pd.amount || 0;
        }
      });
      const el = document.getElementById('stat-revenue');
      if (el) { el.innerHTML = formatCurrency(total); el.classList.add('stat-updated'); setTimeout(() => el.classList.remove('stat-updated'), 500); }
    }, err => console.warn('payments listener:', err))
  );

  // Open tickets count — realtime
  _overviewUnsubscribes.push(
    db.collection('support_tickets').where('status', '==', 'open').onSnapshot(snap => {
      const el = document.getElementById('stat-tickets');
      if (el) { el.textContent = snap.size; el.classList.add('stat-updated'); setTimeout(() => el.classList.remove('stat-updated'), 500); }
      const badge = document.getElementById('nav-ticket-count');
      if (badge) badge.textContent = snap.size;
    }, err => console.error('tickets listener', err))
  );
}

// ============================================
//   REALTIME DOCTORS LIST
// ============================================

let _doctorsListener = null;

function loadDoctorsRealtime() {
  if (_doctorsListener) _doctorsListener();
  _doctorsListener = db.collection('doctors').orderBy('createdAt', 'desc').onSnapshot(snap => {
    allDoctors = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    renderDoctorsTable(allDoctors);
  }, err => console.error('doctors list listener', err));
}

// ============================================
//   REALTIME TICKETS
// ============================================

let _ticketsListener = null;

function loadTicketsRealtime() {
  if (_ticketsListener) _ticketsListener();
  _ticketsListener = db.collection('support_tickets').orderBy('createdAt', 'desc').onSnapshot(snap => {
    allTickets = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    const openCount = allTickets.filter(t => t.status === 'open').length;
    document.getElementById('stat-tickets').textContent = openCount;
    const badge = document.getElementById('nav-ticket-count');
    if (badge) badge.textContent = openCount;
    renderTicketsTable(allTickets);
    // Notify new open tickets
    snap.docChanges().forEach(change => {
      if (change.type === 'added' && change.doc.data().status === 'open') {
        const t = change.doc.data();
        addSystemNotif('ticket', { id: change.doc.id, title: t.title || t.message || 'Support ticket', priority: t.priority || 'medium', user: t.userName || 'User' });
      }
    });
  }, err => console.error('tickets listener', err));
}

// ============================================
//   REALTIME REVENUE
// ============================================

let _revenueListener = null;

function loadRevenueRealtime() {
  if (_revenueListener) _revenueListener();
  _revenueListener = db.collection('payments').orderBy('createdAt', 'desc').onSnapshot(snap => {
    const payments = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    renderPaymentsTable(payments);
    buildRevenueDetailChart(payments);
  }, err => console.error('revenue listener', err));
}

// ============================================
//   REALTIME FEEDBACKS
// ============================================

let _feedbacksListener = null;

function loadFeedbacksRealtime() {
  if (_feedbacksListener) _feedbacksListener();
  _feedbacksListener = db.collection('feedbacks').orderBy('createdAt', 'desc').onSnapshot(snap => {
    allFeedbacks = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    const total     = allFeedbacks.length;
    const immediate = allFeedbacks.filter(f => f.type === 'immediate').length;
    const followup  = allFeedbacks.filter(f => f.type === 'followup').length;
    const ratings   = allFeedbacks.map(f => f.rating || 0).filter(r => r > 0);
    const avg       = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : '—';
    document.getElementById('fb-avg-rating').textContent = avg === '—' ? '—' : `${avg} â­`;
    document.getElementById('fb-total').textContent      = total.toLocaleString();
    document.getElementById('fb-immediate').textContent  = immediate.toLocaleString();
    document.getElementById('fb-followup').textContent   = followup.toLocaleString();
    const badge = document.getElementById('nav-feedback-count');
    if (badge) { badge.textContent = total; badge.style.display = total > 0 ? 'inline' : 'none'; }
    renderFeedbackTable(allFeedbacks);
  }, err => console.error('feedbacks listener', err));
}

// ============================================
//   REALTIME BANNERS
// ============================================

let _bannersListener = null;

function loadBannersRealtime() {
  if (_bannersListener) _bannersListener();
  _bannersListener = db.collection('banners').orderBy('createdAt', 'desc').onSnapshot(snap => {
    allBanners = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    renderBannersList(allBanners);
    const activeCount = allBanners.filter(b => isBannerActive(b)).length;
    const badge = document.getElementById('nav-banner-count');
    if (badge) { badge.textContent = activeCount; badge.style.display = activeCount > 0 ? 'inline' : 'none'; }
  }, err => console.error('banners listener', err));
}

// ============================================
//   PATCH initDashboard — USE REALTIME EVERYWHERE
// ============================================
//   LIVE CALLS — REALTIME DASHBOARD
// ============================================

let _activeCallsListener    = null;
let _completedCallsListener = null;
let _missedCallsListener    = null;
// Tracks elapsed seconds for each active call (keyed by consultationId).
const _callTimers = {};
let _callTickInterval = null;

function initLiveCallsListener() {
  _cleanupCallListeners();

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);

  // ── Active calls (pending + ongoing + active) ──────────────────────────────
  _activeCallsListener = db.collection('consultations')
    .where('status', 'in', ['pending', 'ongoing', 'active'])
    .onSnapshot(snap => {
      const rows = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      _renderActiveCalls(rows);
      _updateCallsStripBadge(rows.length);
    }, err => console.error('[LiveCalls] active listener error:', err));

  // ── Completed today ────────────────────────────────────────────────────────
  _completedCallsListener = db.collection('consultations')
    .where('status', 'in', ['ended', 'completed'])
    .where('createdAt', '>=', todayStart)
    .orderBy('createdAt', 'desc')
    .limit(50)
    .onSnapshot(snap => {
      const rows = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      _renderCompletedCalls(rows);
      animateCounter(document.getElementById('calls-stat-completed'), rows.length);
      document.getElementById('completed-calls-count').textContent = rows.length + ' sessions';
      _computeAvgDuration(rows);
    }, err => console.error('[LiveCalls] completed listener error:', err));

  // ── Missed / declined today ────────────────────────────────────────────────
  _missedCallsListener = db.collection('consultations')
    .where('status', 'in', ['missed', 'declined', 'expired'])
    .where('createdAt', '>=', todayStart)
    .orderBy('createdAt', 'desc')
    .limit(50)
    .onSnapshot(snap => {
      const rows = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      _renderMissedCalls(rows);
      animateCounter(document.getElementById('calls-stat-missed'), rows.length);
      document.getElementById('missed-calls-count').textContent = rows.length + ' calls';
    }, err => console.error('[LiveCalls] missed listener error:', err));

  // Tick every second to update elapsed duration for active calls.
  _callTickInterval = setInterval(_tickActiveCalls, 1000);
}

function _cleanupCallListeners() {
  if (_activeCallsListener)    { _activeCallsListener();    _activeCallsListener    = null; }
  if (_completedCallsListener) { _completedCallsListener(); _completedCallsListener = null; }
  if (_missedCallsListener)    { _missedCallsListener();    _missedCallsListener    = null; }
  if (_callTickInterval)       { clearInterval(_callTickInterval); _callTickInterval = null; }
}

function _updateCallsStripBadge(count) {
  const el = document.getElementById('strip-active-calls');
  if (el) el.textContent = count;
  animateCounter(document.getElementById('calls-stat-active'), count);

  const badge = document.getElementById('nav-calls-count');
  if (badge) {
    if (count > 0) {
      badge.textContent = count;
      badge.style.display = 'inline-block';
    } else {
      badge.style.display = 'none';
    }
  }
  const updated = document.getElementById('active-calls-updated');
  const now = new Date();
  if (updated) updated.textContent = 'Updated ' + now.getHours() + ':' + String(now.getMinutes()).padStart(2,'0') + ':' + String(now.getSeconds()).padStart(2,'0');
}

function _renderActiveCalls(rows) {
  const tbody = document.getElementById('active-calls-tbody');
  if (!tbody) return;
  if (rows.length === 0) {
    tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;padding:32px;color:var(--text-secondary);">No active calls right now</td></tr>';
    return;
  }

  // Seed timer registry for new calls.
  const now = Date.now();
  rows.forEach(r => {
    if (!_callTimers[r.id]) {
      let startMs = now;
      if (r.startedAt && r.startedAt.toDate) startMs = r.startedAt.toDate().getTime();
      else if (r.createdAt && r.createdAt.toDate) startMs = r.createdAt.toDate().getTime();
      _callTimers[r.id] = startMs;
    }
  });
  // Remove stale entries.
  const activeIds = new Set(rows.map(r => r.id));
  Object.keys(_callTimers).forEach(id => { if (!activeIds.has(id)) delete _callTimers[id]; });

  tbody.innerHTML = rows.map(r => {
    const statusColor = r.status === 'active' ? '#1e8e3e' : r.status === 'ongoing' ? '#0277bd' : '#f9a825';
    const statusLabel = r.status === 'active' ? '🟢 In Call' : r.status === 'ongoing' ? '🔵 Joining' : '🟡 Ringing';
    const started = r.startedAt && r.startedAt.toDate
      ? r.startedAt.toDate().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })
      : (r.createdAt && r.createdAt.toDate ? r.createdAt.toDate().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' }) : '—');
    return `<tr data-call-id="${escHtml(r.id)}">
      <td>${escHtml(r.patientName || '—')}</td>
      <td>${escHtml(r.doctorName || '—')}</td>
      <td style="color:var(--text-secondary);font-size:12px;">${escHtml(r.doctorSpecialty || '—')}</td>
      <td>${escHtml(r.consultationType || 'Video')}</td>
      <td>${escHtml(started)}</td>
      <td class="call-duration" data-call-id="${escHtml(r.id)}">—</td>
      <td><span style="background:${statusColor}1a;color:${statusColor};padding:3px 10px;border-radius:12px;font-size:11px;font-weight:700;">${statusLabel}</span></td>
    </tr>`;
  }).join('');
}

function _tickActiveCalls() {
  const now = Date.now();
  document.querySelectorAll('.call-duration[data-call-id]').forEach(el => {
    const id = el.dataset.callId;
    const startMs = _callTimers[id];
    if (!startMs) return;
    const elapsed = Math.floor((now - startMs) / 1000);
    const m = Math.floor(elapsed / 60);
    const s = elapsed % 60;
    el.textContent = m + ':' + String(s).padStart(2, '0');
  });
}

function _renderCompletedCalls(rows) {
  const tbody = document.getElementById('completed-calls-tbody');
  if (!tbody) return;
  if (rows.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:24px;color:var(--text-secondary);">No completed calls today</td></tr>';
    return;
  }
  tbody.innerHTML = rows.map(r => {
    const endedAt = r.endedAt && r.endedAt.toDate
      ? r.endedAt.toDate().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })
      : '—';
    let duration = '—';
    if (r.startedAt && r.endedAt && r.startedAt.toDate && r.endedAt.toDate) {
      const secs = Math.round((r.endedAt.toDate() - r.startedAt.toDate()) / 1000);
      duration = Math.floor(secs / 60) + 'm ' + (secs % 60) + 's';
    }
    return `<tr>
      <td>${escHtml(r.patientName || '—')}</td>
      <td>${escHtml(r.doctorName || '—')}</td>
      <td>${escHtml(r.consultationType || 'Video')}</td>
      <td>${escHtml(duration)}</td>
      <td>${escHtml(endedAt)}</td>
      <td><span style="background:#e8f5e9;color:#1e8e3e;padding:3px 10px;border-radius:12px;font-size:11px;font-weight:700;">✓ Completed</span></td>
    </tr>`;
  }).join('');
}

function _renderMissedCalls(rows) {
  const tbody = document.getElementById('missed-calls-tbody');
  if (!tbody) return;
  if (rows.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;padding:24px;color:var(--text-secondary);">No missed calls today</td></tr>';
    return;
  }
  tbody.innerHTML = rows.map(r => {
    const createdAt = r.createdAt && r.createdAt.toDate
      ? r.createdAt.toDate().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })
      : '—';
    const reasonColor = r.status === 'declined' ? '#e65100' : '#b71c1c';
    const reasonLabel = r.status === 'declined' ? 'Declined' : r.status === 'expired' ? 'Expired' : 'Missed';
    return `<tr>
      <td>${escHtml(r.patientName || '—')}</td>
      <td>${escHtml(r.doctorName || '—')}</td>
      <td>${escHtml(r.consultationType || 'Video')}</td>
      <td>${escHtml(createdAt)}</td>
      <td><span style="background:${reasonColor}1a;color:${reasonColor};padding:3px 10px;border-radius:12px;font-size:11px;font-weight:700;">${escHtml(reasonLabel)}</span></td>
    </tr>`;
  }).join('');
}

function _computeAvgDuration(rows) {
  const el = document.getElementById('calls-stat-avg-duration');
  if (!el) return;
  const valid = rows.filter(r => r.startedAt && r.endedAt && r.startedAt.toDate && r.endedAt.toDate);
  if (valid.length === 0) { el.textContent = '—'; return; }
  const totalMins = valid.reduce((sum, r) => {
    return sum + (r.endedAt.toDate() - r.startedAt.toDate()) / 60000;
  }, 0);
  el.textContent = (totalMins / valid.length).toFixed(1);
}

// Wire Live Calls tab initialisation on first navigation to that tab.
let _liveCallsInited = false;
document.addEventListener('DOMContentLoaded', () => {
  document.querySelector('.nav-item[data-tab="calls"]')?.addEventListener('click', () => {
    if (!_liveCallsInited) {
      _liveCallsInited = true;
      initLiveCallsListener();
    }
  });
});

// ============================================

function initDashboard() {
  initOverviewRealtime();
  loadDoctorsRealtime();
  loadPatients();
  loadRevenueRealtime();
  loadMedicines();
  loadTicketsRealtime();
  loadReportsList();
  loadBannersRealtime();
  loadHospitals();
  loadAmbulances();
  initReferralSettingsListener();
  initReferralsListener();
  loadFeedbacksRealtime();
  initRequestsListener();
  initNotificationsListener();
  initServicesListener();
  initMedicinesCatalogueListener();
  initAppointmentsListener();
  initWalletListener();
  loadBroadcasts();
  loadSpecRequests();
  loadReviews();
  loadQualityAnalytics();
  initMaternityListeners();
  loadLiveStrip();
  startRealtimeRevenue();
  initConnectionMonitor();
  updateAdminDisplayName();
  updateLastRefreshTime();
  // Always start the active-calls badge listener regardless of which tab is active,
  // so the strip counter and nav badge update in realtime from the first login.
  initLiveCallsListener();
  _liveCallsInited = true;
  initCaregiversListener();
  initCareAssistantsListener();
}

function updateAdminDisplayName() {
  const user = auth.currentUser;
  if (!user) return;
  const name = user.displayName || user.email || 'Admin';
  const el = document.querySelector('.admin-name');
  if (el) el.textContent = name.split('@')[0];
}

// ============================================
//   MEDICINES CATALOGUE — FULL CRUD
// ============================================

let _allMedCat         = [];
let _editingMedCatId   = null;
let _medCatListener    = null;

function initMedicinesCatalogueListener() {
  if (_medCatListener) _medCatListener();
  _medCatListener = db.collection('medicines_catalogue')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      _allMedCat = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      renderMedCatList();
    }, err => console.error('[MedCat]', err));
}

function renderMedCatList() {
  const tbody = document.getElementById('med-cat-tbody');
  if (!tbody) return;
  const countEl = document.getElementById('med-cat-count-label');
  if (countEl) countEl.textContent = `${_allMedCat.length} medicine${_allMedCat.length !== 1 ? 's' : ''}`;

  if (_allMedCat.length === 0) {
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:var(--text-muted);padding:24px;">No medicines in catalogue yet. Add one above.</td></tr>';
    return;
  }

  tbody.innerHTML = _allMedCat.map(m => `
    <tr>
      <td><strong>${escHtml(m.name || '')}</strong></td>
      <td>${escHtml(m.brand || '')}</td>
      <td>₹${escHtml(String(m.price || 0))}</td>
      <td>₹${escHtml(String(m.mrp || 0))}</td>
      <td>${escHtml(String(m.qty || 1))} ${escHtml(m.unit || 'Tablets')}</td>
      <td>${m.requiresPrescription ? '<span style="color:#e65100;font-weight:700;">Rx</span>' : '—'}</td>
      <td>
        <span style="display:inline-flex;align-items:center;gap:5px;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;
          background:${m.isActive !== false ? '#e8f5e9' : '#fce4ec'};
          color:${m.isActive !== false ? '#2e7d32' : '#c62828'};">
          ${m.isActive !== false ? 'Active' : 'Hidden'}
        </span>
      </td>
      <td>
        <div style="display:flex;gap:6px;">
          <button onclick="editMedCat('${escHtml(m.id)}')" class="btn btn-sm btn-outline" title="Edit">
            <i class="ti ti-pencil"></i>
          </button>
          <button onclick="toggleMedCatActive('${escHtml(m.id)}', ${m.isActive !== false})" class="btn btn-sm btn-outline" title="${m.isActive !== false ? 'Hide' : 'Show'}">
            <i class="ti ti-${m.isActive !== false ? 'eye-off' : 'eye'}"></i>
          </button>
          <button onclick="deleteMedCat('${escHtml(m.id)}')" class="btn btn-sm btn-outline" style="color:var(--danger);" title="Delete">
            <i class="ti ti-trash"></i>
          </button>
        </div>
      </td>
    </tr>
  `).join('');
}

async function saveMedicineCatalogue() {
  const name  = (document.getElementById('med-cat-name')?.value  || '').trim();
  const brand = (document.getElementById('med-cat-brand')?.value || '').trim();
  const price = parseInt(document.getElementById('med-cat-price')?.value || '0', 10);
  const mrp   = parseInt(document.getElementById('med-cat-mrp')?.value   || '0', 10);
  const qty   = parseInt(document.getElementById('med-cat-qty')?.value   || '1', 10);
  const unit  = document.getElementById('med-cat-unit')?.value  || 'Tablets';
  const rx    = document.getElementById('med-cat-rx')?.checked  || false;
  const active = document.getElementById('med-cat-active')?.checked !== false;

  if (!name || !brand) { showToast('Medicine name and brand are required.'); return; }
  if (!price || price <= 0) { showToast('Enter a valid selling price.'); return; }

  const data = {
    name, brand, price, mrp: mrp || price, qty: qty || 1, unit,
    requiresPrescription: rx,
    isActive: active,
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  };

  const btn = document.querySelector('[onclick="saveMedicineCatalogue()"]');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="ti ti-loader"></i> Saving…'; }

  try {
    if (_editingMedCatId) {
      await db.collection('medicines_catalogue').doc(_editingMedCatId).update(data);
      showToast('Medicine updated âœ“');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('medicines_catalogue').add(data);
      showToast('Medicine added to catalogue âœ“');
    }
    cancelMedicineCatalogueEdit();
  } catch (e) {
    showToast('Save failed: ' + e.message);
  } finally {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="ti ti-device-floppy"></i> <span id="med-cat-save-label">Add Medicine</span>'; }
  }
}

function editMedCat(id) {
  const m = _allMedCat.find(x => x.id === id);
  if (!m) return;
  _editingMedCatId = id;

  const setVal = (elId, val) => { const el = document.getElementById(elId); if (el) el.value = val ?? ''; };
  setVal('med-cat-name',  m.name  || '');
  setVal('med-cat-brand', m.brand || '');
  setVal('med-cat-price', m.price || 0);
  setVal('med-cat-mrp',   m.mrp   || 0);
  setVal('med-cat-qty',   m.qty   || 1);
  setVal('med-cat-unit',  m.unit  || 'Tablets');

  const rxEl  = document.getElementById('med-cat-rx');
  const actEl = document.getElementById('med-cat-active');
  if (rxEl)  rxEl.checked  = m.requiresPrescription || false;
  if (actEl) actEl.checked = m.isActive !== false;

  const saveLabel = document.getElementById('med-cat-save-label');
  const cancelBtn = document.getElementById('med-cat-cancel');
  if (saveLabel) saveLabel.textContent = 'Update Medicine';
  if (cancelBtn) cancelBtn.style.display = 'inline-flex';

  document.getElementById('med-cat-name')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function cancelMedicineCatalogueEdit() {
  _editingMedCatId = null;
  ['med-cat-name','med-cat-brand','med-cat-price','med-cat-mrp','med-cat-qty'].forEach(id => {
    const el = document.getElementById(id); if (el) el.value = '';
  });
  const unitEl = document.getElementById('med-cat-unit');
  if (unitEl) unitEl.value = 'Tablets';
  const rxEl = document.getElementById('med-cat-rx');
  if (rxEl) rxEl.checked = false;
  const actEl = document.getElementById('med-cat-active');
  if (actEl) actEl.checked = true;
  const saveLabel = document.getElementById('med-cat-save-label');
  if (saveLabel) saveLabel.textContent = 'Add Medicine';
  const cancelBtn = document.getElementById('med-cat-cancel');
  if (cancelBtn) cancelBtn.style.display = 'none';
}

async function toggleMedCatActive(id, currentlyActive) {
  try {
    await db.collection('medicines_catalogue').doc(id).update({
      isActive: !currentlyActive,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast(currentlyActive ? 'Medicine hidden from app' : 'Medicine visible in app âœ“');
  } catch (e) { showToast('Update failed: ' + e.message); }
}

async function deleteMedCat(id) {
  if (!confirm('Delete this medicine from the catalogue? This cannot be undone.')) return;
  try {
    await db.collection('medicines_catalogue').doc(id).delete();
    showToast('Medicine deleted');
  } catch (e) { showToast('Delete failed: ' + e.message); }
}

// Show/hide equipment-only fields (deposit, buy price) and adjust price
// labelling/unit visibility based on the active service category. Equipment
// rent pricing is always per-day, so the generic Price Unit picker is hidden
// and a dedicated Buy Price field is shown instead.
function _syncEquipmentFields() {
  const isEquipment = _activeServiceCategory === 'equipment';
  const depositGroup  = document.getElementById('svc-deposit-group');
  const buyPriceGroup = document.getElementById('svc-buy-price-group');
  const priceUnitGroup = document.getElementById('svc-price-unit-group');
  const priceLabel    = document.getElementById('svc-price-label');
  if (depositGroup)   depositGroup.style.display   = isEquipment ? 'block' : 'none';
  if (buyPriceGroup)  buyPriceGroup.style.display  = isEquipment ? 'block' : 'none';
  if (priceUnitGroup) priceUnitGroup.style.display = isEquipment ? 'none'  : 'block';
  if (priceLabel)     priceLabel.textContent       = isEquipment ? 'Rent Price / Day (₹)' : 'Price (₹)';
}

// Patch openServiceCategory to toggle equipment-only fields
const _origOpenServiceCategory = openServiceCategory;
function openServiceCategory(key) {
  _origOpenServiceCategory(key);
  _syncEquipmentFields();
}


// ============================================
//   SERVICES MANAGEMENT — FULL CRUD
// ============================================

let allServices           = [];
let _editingServiceId     = null;
let _servicesListener     = null;
let _activeServiceCategory = null;

const svcTypeColors = {
  diagnostics:      { bg: '#e0f7fa', fg: '#0097a7', icon: '' },
  lab_tests:        { bg: '#e8eaf6', fg: '#3949ab', icon: '' },
  physiotherapy:    { bg: '#e3f2fd', fg: '#1565c0', icon: '' },
  care_assistant:   { bg: '#fff3e0', fg: '#e65100', icon: '' },
  caregivers:       { bg: '#fce4ec', fg: '#c2185b', icon: '' },
  equipment:        { bg: '#eceff1', fg: '#37474f', icon: '' },
  consultation:     { bg: '#f3e5f5', fg: '#7b1fa2', icon: '' },
  nutrition:        { bg: '#e8f5e9', fg: '#2e7d32', icon: '' },
  counselling:      { bg: '#e0f2f1', fg: '#00695c', icon: ' ' },
  medicine_delivery:{ bg: '#fff8e1', fg: '#f57f17', icon: '' },
};

function svcTypeLabel(type) {
  const m = {
    diagnostics:'Diagnostics', lab_tests:'Lab Tests', physiotherapy:'Physiotherapy',
    care_assistant:'Care Assistant', caregivers:'Caregivers', equipment:'Equipment',
    consultation:'Consultation', nutrition:'Nutrition', counselling:'Counselling',
    medicine_delivery:'Medicine Delivery',
  };
  return m[type] || capitalize(type || 'Service');
}

function initServicesListener() {
  if (_servicesListener) _servicesListener();
  _servicesListener = db.collection('services').orderBy('createdAt', 'desc').onSnapshot(snap => {
    allServices = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    filterServices();

    // Nav badge
    const enabledCount = allServices.filter(s => s.isEnabled).length;
    const badge = document.getElementById('nav-services-count');
    if (badge) { badge.textContent = enabledCount; badge.style.display = enabledCount > 0 ? 'inline' : 'none'; }

    // Update hub counts per category
    const catKeys = ['diagnostics','lab_tests','physiotherapy','care_assistant','caregivers','equipment','consultation','nutrition','counselling','medicine_delivery'];
    catKeys.forEach(key => {
      const count = allServices.filter(s => s.type === key).length;
      const el = document.getElementById(`hub-count-${key}`);
      if (el) el.textContent = count === 0 ? 'No services' : `${count} service${count !== 1 ? 's' : ''}`;
    });
  }, err => console.error('services listener', err));
}

function filterServices() {
  const q      = (document.getElementById('service-search')?.value || '').toLowerCase();
  let filtered = allServices;
  if (_activeServiceCategory) filtered = filtered.filter(s => s.type === _activeServiceCategory);
  if (q) filtered = filtered.filter(s =>
    (s.name || '').toLowerCase().includes(q) ||
    (s.description || '').toLowerCase().includes(q)
  );
  renderServicesList(filtered);

  const countEl = document.getElementById('cat-view-count-label');
  if (countEl && _activeServiceCategory) {
    countEl.textContent = `${filtered.length} service${filtered.length !== 1 ? 's' : ''}`;
  }
}

function openServiceCategory(key) {
  _activeServiceCategory = key;
  cancelServiceEdit();

  const tc    = svcTypeColors[key] || { bg: '#f3e5f5', fg: '#7b1fa2', icon: '' };
  const label = svcTypeLabel(key);

  // Category detail header
  document.getElementById('cat-view-icon-lg').innerHTML =
    `<div style="width:52px;height:52px;border-radius:14px;background:${tc.bg};color:${tc.fg};display:flex;align-items:center;justify-content:center;font-size:26px;">${tc.icon}</div>`;
  document.getElementById('cat-view-name').textContent = label;
  document.getElementById('cat-services-list-title').textContent = label + ' Services';

  // Lock category in form
  document.getElementById('svc-type').value = key;
  document.getElementById('svc-type-display').innerHTML =
    `<span style="font-size:16px;line-height:1;">${tc.icon}</span><span style="color:var(--text-secondary);font-size:13px;">${label} (auto-assigned)</span>`;

  // Show detail, hide hub
  document.getElementById('services-hub').style.display     = 'none';
  document.getElementById('services-cat-view').style.display = 'block';

  // Update topbar page subtitle
  document.getElementById('page-sub').textContent = 'Services › ' + label;

  filterServices();
}

function backToServicesHub() {
  _activeServiceCategory = null;
  document.getElementById('services-hub').style.display     = 'block';
  document.getElementById('services-cat-view').style.display = 'none';
  document.getElementById('page-sub').textContent =
    new Date().toLocaleDateString('en-IN', { weekday:'long', year:'numeric', month:'long', day:'numeric' });
}

function renderServicesList(services) {
  const el = document.getElementById('services-list');
  if (!el) return;
  if (!services.length) {
    el.innerHTML = '<div class="empty-state"><div class="empty-icon"> </div><p>No services added yet — create one above.</p></div>';
    return;
  }
  el.innerHTML = services.map(s => {
    const tc      = svcTypeColors[s.type] || { bg: '#f3e5f5', fg: '#6a1b9a', icon: '' };
    const priceStr = s.price
      ? `₹${Number(s.price).toLocaleString('en-IN')} <span style="font-size:11px;font-weight:400;color:var(--text-muted);">${s.priceUnit ? '/ '+s.priceUnit.replace('_',' ') : ''}</span>`
      : '<span style="color:var(--text-muted);font-size:12px;">Price not set</span>';
    const buyPriceStr = (s.type === 'equipment' && s.purchasePrice)
      ? `<span class="service-price">Buy: ₹${Number(s.purchasePrice).toLocaleString('en-IN')}</span>`
      : '';
    const thumb = s.imageUrl
      ? `<img class="service-thumb" src="${escHtml(s.imageUrl)}" alt="${escHtml(s.name || '')}" loading="lazy" />`
      : `<div class="service-thumb-placeholder" style="background:${tc.bg};color:${tc.fg};">${tc.icon}</div>`;
    return `
    <div class="service-card" id="service-card-${s.id}">
      ${thumb}
      <div class="service-info">
        <div class="service-name">${escHtml(s.name || '—')}</div>
        <div class="service-meta">${escHtml(s.description || '')}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px;align-items:center;">
          <span class="svc-type-badge" style="background:${tc.bg};color:${tc.fg};">${tc.icon} ${svcTypeLabel(s.type)}</span>
          <span class="service-price">${priceStr}</span>
          ${buyPriceStr}
          ${s.duration ? `<span class="banner-cta-chip">â± ${escHtml(s.duration)}</span>` : ''}
          ${s.isFeatured ? '<span class="pill pill-active">â­ Featured</span>' : ''}
          ${s.isEnabled ? '<span class="pill pill-active">Enabled</span>' : '<span class="pill pill-suspended">Disabled</span>'}
        </div>
      </div>
      <div class="service-actions">
        <label class="toggle-label" title="${s.isEnabled ? 'Disable' : 'Enable'}">
          <input type="checkbox" ${s.isEnabled ? 'checked' : ''} onchange="toggleService('${s.id}', this.checked)" />
          <span class="toggle-switch"></span>
        </label>
        <button class="btn btn-outline" onclick="editService('${s.id}')" title="Edit">
          <i class="ti ti-edit"></i>
        </button>
        <button class="btn btn-reject" onclick="deleteService('${s.id}', '${escHtml(s.storagePath||'')}', this)" title="Delete">
          <i class="ti ti-trash"></i>
        </button>
      </div>
    </div>`;
  }).join('');
}

async function saveService() {
  const name        = document.getElementById('svc-name')?.value.trim();
  const type        = document.getElementById('svc-type')?.value;
  const price       = document.getElementById('svc-price')?.value;
  const priceUnit   = document.getElementById('svc-price-unit')?.value;
  const duration    = document.getElementById('svc-duration')?.value.trim();
  const description = document.getElementById('svc-desc')?.value.trim();
  const isEnabled   = document.getElementById('svc-enabled')?.checked !== false;
  const isFeatured  = document.getElementById('svc-featured')?.checked || false;
  const depositRaw  = document.getElementById('svc-deposit')?.value;
  const deposit     = type === 'equipment' && depositRaw ? parseFloat(depositRaw) : null;
  const buyPriceRaw = document.getElementById('svc-buy-price')?.value;
  const purchasePrice = type === 'equipment' && buyPriceRaw ? parseFloat(buyPriceRaw) : null;
  const fileInput   = document.getElementById('service-file-input');
  const file        = fileInput?.files[0];

  if (!name) { showToast('Service name is required'); return; }
  if (!type)  { showToast('Please select a category'); return; }

  const btn      = document.getElementById('save-service-btn');
  const progress = document.getElementById('service-upload-progress');
  btn.disabled   = true;

  let imageUrl    = '';
  let storagePath = '';

  if (_editingServiceId && !file) {
    const existing = allServices.find(s => s.id === _editingServiceId);
    imageUrl    = existing?.imageUrl    || '';
    storagePath = existing?.storagePath || '';
  }

  if (file) {
    if (file.size > 5 * 1024 * 1024) { showToast('Image too large — max 5 MB'); btn.disabled = false; return; }
    progress.style.display = 'flex';
    btn.style.display = 'none';
    const safeName  = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    storagePath     = `services/${Date.now()}_${safeName}`;
    try {
      const ref  = storage.ref(storagePath);
      const task = ref.put(file, { contentType: file.type });
      await new Promise((res, rej) => task.on('state_changed', null, rej, res));
      imageUrl = await ref.getDownloadURL();
    } catch (err) {
      showToast('Upload failed: ' + err.message);
      progress.style.display = 'none';
      btn.style.display = 'inline-flex';
      btn.disabled = false;
      return;
    }
    progress.style.display = 'none';
    btn.style.display = 'inline-flex';
  }

  const data = {
    name, type,
    price:       price ? parseFloat(price) : null,
    priceUnit:   type === 'equipment' ? 'per_day' : (priceUnit || 'per_session'),
    duration:    duration   || null,
    description: description || null,
    deposit:     deposit,
    purchasePrice: purchasePrice,
    imageUrl, storagePath,
    isEnabled, isFeatured,
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    updatedBy: auth.currentUser?.email || 'admin',
  };

  try {
    if (_editingServiceId) {
      await db.collection('services').doc(_editingServiceId).update(data);
      showToast('Service updated âœ“');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('services').add(data);
      showToast('Service added âœ“');
    }
    cancelServiceEdit();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    btn.disabled = false;
  }
}

function editService(id) {
  const s = allServices.find(x => x.id === id);
  if (!s) return;
  _editingServiceId = id;
  document.getElementById('svc-name').value       = s.name        || '';
  document.getElementById('svc-type').value       = s.type        || _activeServiceCategory || 'diagnostics';
  document.getElementById('svc-price').value      = s.price       || '';
  document.getElementById('svc-price-unit').value = s.priceUnit   || 'per_session';
  document.getElementById('svc-duration').value   = s.duration    || '';
  document.getElementById('svc-desc').value       = s.description || '';
  document.getElementById('svc-enabled').checked  = s.isEnabled   !== false;
  document.getElementById('svc-featured').checked = s.isFeatured  || false;
  const depositInput = document.getElementById('svc-deposit');
  if (depositInput) depositInput.value = s.deposit || '';
  const buyPriceInput = document.getElementById('svc-buy-price');
  if (buyPriceInput) buyPriceInput.value = s.purchasePrice || '';
  _syncEquipmentFields();
  if (s.imageUrl) {
    const img = document.getElementById('service-preview-img');
    img.src = s.imageUrl; img.style.display = 'block';
    document.getElementById('service-upload-placeholder').style.display = 'none';
  }
  document.getElementById('service-form-title').textContent = 'Edit Service';
  document.getElementById('save-service-btn').innerHTML     = '<i class="ti ti-device-floppy"></i> Save Changes';
  document.getElementById('cancel-service-btn').style.display = 'inline-flex';
  document.getElementById('services-cat-view').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function cancelServiceEdit() {
  _editingServiceId = null;
  ['svc-name','svc-price','svc-duration','svc-desc','svc-deposit','svc-buy-price'].forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
  const typeEl = document.getElementById('svc-type');
  if (typeEl) typeEl.value = _activeServiceCategory || 'diagnostics';
  const puEl = document.getElementById('svc-price-unit'); if (puEl) puEl.value = 'per_session';
  const enabledEl = document.getElementById('svc-enabled');   if (enabledEl)  enabledEl.checked  = true;
  const featuredEl = document.getElementById('svc-featured'); if (featuredEl) featuredEl.checked = false;
  const fi = document.getElementById('service-file-input'); if (fi) fi.value = '';
  const pi = document.getElementById('service-preview-img'); if (pi) pi.style.display = 'none';
  const ph = document.getElementById('service-upload-placeholder'); if (ph) ph.style.display = 'block';
  const ft = document.getElementById('service-form-title'); if (ft) ft.textContent = 'Add Service';
  const sb = document.getElementById('save-service-btn');
  if (sb) sb.innerHTML = '<i class="ti ti-device-floppy"></i> Save Service';
  const cb = document.getElementById('cancel-service-btn'); if (cb) cb.style.display = 'none';
}

function previewServiceImage(event) {
  const file = event.target.files[0];
  if (!file) return;
  if (file.size > 5 * 1024 * 1024) { showToast('Image too large — max 5 MB'); event.target.value = ''; return; }
  const reader = new FileReader();
  reader.onload = e => {
    const img = document.getElementById('service-preview-img');
    img.src = e.target.result; img.style.display = 'block';
    document.getElementById('service-upload-placeholder').style.display = 'none';
  };
  reader.readAsDataURL(file);
}

async function toggleService(id, enabled) {
  try {
    await db.collection('services').doc(id).update({ isEnabled: enabled, updatedAt: firebase.firestore.FieldValue.serverTimestamp() });
    showToast(enabled ? 'Service enabled âœ“' : 'Service disabled');
  } catch (err) { showToast('Update failed: ' + err.message); }
}

async function deleteService(id, storagePath, btn) {
  if (!confirm('Delete this service? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    await db.collection('services').doc(id).delete();
    if (storagePath) { try { await storage.ref(storagePath).delete(); } catch(_) {} }
    showToast('Service deleted');
  } catch (err) { btn.disabled = false; showToast('Delete failed: ' + err.message); }
}

// Drag-and-drop for service image
document.addEventListener('DOMContentLoaded', () => {
  const zone = document.getElementById('service-upload-zone');
  if (!zone) return;
  zone.addEventListener('dragover',  e => { e.preventDefault(); zone.classList.add('drag-over'); });
  zone.addEventListener('dragleave', () => zone.classList.remove('drag-over'));
  zone.addEventListener('drop', e => {
    e.preventDefault(); zone.classList.remove('drag-over');
    const file = e.dataTransfer?.files?.[0];
    if (file && file.type.startsWith('image/')) {
      const dt = new DataTransfer(); dt.items.add(file);
      document.getElementById('service-file-input').files = dt.files;
      previewServiceImage({ target: { files: dt.files, value: '' } });
    }
  });
});

// ============================================
//   APPOINTMENTS MANAGEMENT — REALTIME
// ============================================

let _allAppointments     = [];
let _apptListener        = null;

function initAppointmentsListener() {
  if (_apptListener) _apptListener();
  _apptListener = db.collection('appointments').orderBy('createdAt', 'desc').onSnapshot(snap => {
    _allAppointments = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    updateApptStats();
    applyApptFilters();
    updateApptBadge();
  }, err => console.error('appointments listener', err));
}

function updateApptStats() {
  const today = new Date().toISOString().slice(0, 10);
  const counts = { pending: 0, confirmed: 0, completed: 0, cancelled: 0, today: 0 };
  _allAppointments.forEach(a => {
    const s = a.status || 'pending';
    if (s in counts) counts[s]++;
    if (a.date === today) counts.today++;
  });
  ['pending','confirmed','completed','cancelled','today'].forEach(k => {
    const el = document.getElementById(`appt-stat-${k}`);
    if (el) el.textContent = counts[k];
  });
}

function updateApptBadge() {
  const pending = _allAppointments.filter(a => !a.status || a.status === 'pending').length;
  const badge   = document.getElementById('nav-appt-count');
  if (!badge) return;
  badge.textContent   = pending;
  badge.style.display = pending > 0 ? 'inline-flex' : 'none';
}

function applyApptFilters() {
  const q       = (document.getElementById('appt-search')?.value || '').toLowerCase();
  const status  = document.getElementById('appt-status-filter')?.value || 'all';
  const dateF   = document.getElementById('appt-date-filter')?.value  || 'all';
  const today   = new Date().toISOString().slice(0, 10);
  const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
  const monAgo  = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);

  let list = _allAppointments;
  if (status !== 'all') list = list.filter(a => (a.status || 'pending') === status);
  if (dateF === 'today') list = list.filter(a => a.date === today);
  else if (dateF === 'week')  list = list.filter(a => a.date >= weekAgo);
  else if (dateF === 'month') list = list.filter(a => a.date >= monAgo);
  if (q) list = list.filter(a =>
    (a.patientName || '').toLowerCase().includes(q) ||
    (a.doctorName  || '').toLowerCase().includes(q) ||
    (a.patientPhone || '').toLowerCase().includes(q)
  );

  const label = document.getElementById('appt-count-label');
  if (label) label.textContent = `${list.length} appointment${list.length !== 1 ? 's' : ''}`;
  renderAppointmentsTable(list);
}

function renderAppointmentsTable(list) {
  const tbody = document.getElementById('appointments-tbody');
  if (!tbody) return;
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="loading">No appointments found</td></tr>';
    return;
  }
  tbody.innerHTML = list.map(a => {
    const status = a.status || 'pending';
    const pillCls = { pending:'pending', confirmed:'confirmed', completed:'completed', cancelled:'suspended', no_show:'no_show' }[status] || 'pending';
    const patColor = randomAvatarColor(a.patientName);
    const typeBadge = a.type === 'video'
      ? '<span class="pill" style="background:#e3f2fd;color:#1565c0;"> Video</span>'
      : '<span class="pill" style="background:#e8f5e9;color:#2e7d32;"> In-Person</span>';
    const slot = [a.date, a.time].filter(Boolean).join(' &middot; ') || '—';
    return `<tr>
      <td>
        <div class="user-cell">
          <div class="doc-avatar" style="background:${patColor.bg};color:${patColor.fg};">${getInitials(a.patientName||'PT')}</div>
          <div><div class="user-name">${a.patientName||'—'}</div><div class="user-sub">${a.patientPhone||''}</div></div>
        </div>
      </td>
      <td>
        <div class="user-name">${a.doctorName||'—'}</div>
        <div class="user-sub">${a.doctorSpeciality||''}</div>
      </td>
      <td><span class="appt-time-badge">${slot}</span></td>
      <td>${typeBadge}</td>
      <td><span class="pill pill-${pillCls}">${capitalize(status.replace('_',' '))}</span></td>
      <td style="font-size:12px;color:var(--text-secondary);">${formatDate(a.createdAt)}</td>
      <td>
        <div style="display:flex;gap:4px;flex-wrap:wrap;">
          ${status === 'pending' ? `
            <button class="btn btn-approve" onclick="updateApptStatus('${a.id}','confirmed',this)">Confirm</button>
            <button class="btn btn-reject"  onclick="updateApptStatus('${a.id}','cancelled',this)">Cancel</button>
          ` : ''}
          ${status === 'confirmed' ? `
            <button class="btn btn-approve" onclick="updateApptStatus('${a.id}','completed',this)">Complete</button>
            <button class="btn btn-reject"  onclick="updateApptStatus('${a.id}','cancelled',this)">Cancel</button>
          ` : ''}
          <button class="btn btn-outline" onclick="viewApptDetail('${a.id}')">View</button>
        </div>
      </td>
    </tr>`;
  }).join('');
}

async function updateApptStatus(id, newStatus, btn) {
  if (btn) { btn.disabled = true; btn.textContent = '…'; }
  try {
    await db.collection('appointments').doc(id).update({
      status: newStatus,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    // Notify patient
    const appt = _allAppointments.find(a => a.id === id);
    if (appt?.patientId) {
      const msg = {
        confirmed: 'Your appointment has been confirmed!',
        cancelled: 'Your appointment has been cancelled.',
        completed: 'Your appointment is marked as completed.',
      }[newStatus];
      if (msg) {
        // Correct path: patient_notifications/{uid}/items
        db.collection('patient_notifications').doc(appt.patientId).collection('items').add({
          title: 'Appointment Update',
          body: msg,
          type: 'appointment',
          isRead: false,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          deliverAt: firebase.firestore.FieldValue.serverTimestamp(),
        }).catch(() => {});
      }
    }
    showToast(`Appointment ${newStatus} âœ“`);
  } catch (err) {
    showToast('Update failed: ' + err.message);
    if (btn) { btn.disabled = false; btn.textContent = capitalize(newStatus); }
  }
}

function viewApptDetail(id) {
  const a = _allAppointments.find(x => x.id === id);
  if (!a) return;
  document.getElementById('appt-detail-modal')?.remove();
  const status = a.status || 'pending';
  const pillCls = { pending:'pending', confirmed:'confirmed', completed:'completed', cancelled:'suspended', no_show:'no_show' }[status] || 'pending';
  const modal = document.createElement('div');
  modal.id = 'appt-detail-modal';
  modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px;';
  modal.innerHTML = `
    <div style="background:#fff;border-radius:20px;width:100%;max-width:500px;max-height:90vh;overflow-y:auto;padding:28px;">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;">
        <h2 style="font-size:18px;font-weight:700;margin:0;">Appointment Detail</h2>
        <button onclick="document.getElementById('appt-detail-modal').remove()" style="border:none;background:none;font-size:22px;cursor:pointer;color:#666;">&times;</button>
      </div>
      <div style="background:#f9f9f9;border-radius:14px;padding:16px;margin-bottom:18px;">
        <div style="font-size:16px;font-weight:700;">${a.patientName||'—'}</div>
        <div style="font-size:13px;color:#888;margin-top:2px;">${a.patientPhone||''}</div>
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:16px;">
        ${[['Doctor', a.doctorName||'—'], ['Speciality', a.doctorSpeciality||'—'], ['Date', a.date||'—'], ['Time', a.time||'—'], ['Type', capitalize(a.type||'in_person')], ['Status', capitalize(status)]].map(([l,v])=>`
          <div style="padding:10px;background:#f9f9f9;border-radius:10px;">
            <div style="font-size:11px;color:#aaa;font-weight:600;">${l.toUpperCase()}</div>
            <div style="font-size:14px;font-weight:600;margin-top:2px;">${v}</div>
          </div>`).join('')}
      </div>
      ${a.notes ? `<div style="padding:12px;background:#fffde7;border-radius:10px;margin-bottom:16px;"><div style="font-size:11px;font-weight:600;color:#f9a825;margin-bottom:4px;">NOTES</div><div style="font-size:13px;">${a.notes}</div></div>` : ''}
      <div style="display:flex;gap:8px;flex-wrap:wrap;">
        ${status==='pending' ? `
          <button class="btn btn-approve" style="flex:1;" onclick="updateApptStatus('${a.id}','confirmed',this);document.getElementById('appt-detail-modal').remove();">Confirm</button>
          <button class="btn btn-reject" onclick="updateApptStatus('${a.id}','cancelled',this);document.getElementById('appt-detail-modal').remove();">Cancel</button>
        ` : ''}
        ${status==='confirmed' ? `
          <button class="btn btn-approve" style="flex:1;" onclick="updateApptStatus('${a.id}','completed',this);document.getElementById('appt-detail-modal').remove();">Mark Completed</button>
        ` : ''}
        <button class="btn btn-outline" onclick="document.getElementById('appt-detail-modal').remove()">Close</button>
      </div>
    </div>`;
  document.body.appendChild(modal);
  modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
}

// ============================================
//   WALLET & TRANSACTIONS MANAGEMENT
// ============================================

let _allWalletTx   = [];
let _walletListener = null;
let _selectedWalletUser = null;

function initWalletListener() {
  if (_walletListener) _walletListener();
  // Listen to top-level wallet_transactions collection
  _walletListener = db.collection('wallet_transactions').orderBy('createdAt', 'desc').limit(200).onSnapshot(snap => {
    _allWalletTx = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    updateWalletStats();
    filterWalletTx();
    // Badge: pending refunds
    const refunds = _allWalletTx.filter(t => t.type === 'refund' && t.status === 'pending').length;
    const badge = document.getElementById('nav-wallet-count');
    if (badge) { badge.textContent = refunds; badge.style.display = refunds > 0 ? 'inline-flex' : 'none'; }
  }, err => console.error('wallet listener', err));
}

function updateWalletStats() {
  let credits = 0, debits = 0, refunds = 0, referrals = 0;
  _allWalletTx.forEach(t => {
    if (t.type === 'credit')   credits   += t.amount || 0;
    if (t.type === 'debit')    debits    += t.amount || 0;
    if (t.type === 'refund')   refunds   += (t.status === 'pending') ? 1 : 0;
    if (t.type === 'referral') referrals += t.amount || 0;
  });
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  set('wallet-stat-credits',  formatCurrency(credits));
  set('wallet-stat-debits',   formatCurrency(debits));
  set('wallet-stat-refunds',  refunds.toString());
  set('wallet-stat-referral', formatCurrency(referrals));
}

function filterWalletTx() {
  const q    = (document.getElementById('wallet-search')?.value || '').toLowerCase();
  const type = document.getElementById('wallet-type-filter')?.value || 'all';
  let list   = _allWalletTx;
  if (type !== 'all') list = list.filter(t => t.type === type);
  if (q) list = list.filter(t =>
    (t.userName  || '').toLowerCase().includes(q) ||
    (t.userPhone || '').toLowerCase().includes(q) ||
    (t.reason    || '').toLowerCase().includes(q)
  );
  renderWalletTable(list);
}

function renderWalletTable(list) {
  const tbody = document.getElementById('wallet-tbody');
  if (!tbody) return;
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="6" class="loading">No transactions found</td></tr>';
    return;
  }
  const typeClass  = { credit:'wallet-credit', debit:'wallet-debit', refund:'wallet-refund', referral:'wallet-referral' };
  const typeLabel  = { credit:'Credit', debit:'Debit', refund:'Refund', referral:'Referral' };
  const typeSign   = { credit:'+', debit:'-', refund:'+', referral:'+' };
  tbody.innerHTML = list.slice(0, 100).map(t => {
    const tc  = typeClass[t.type]  || 'wallet-credit';
    const tl  = typeLabel[t.type]  || capitalize(t.type||'');
    const sign = typeSign[t.type] || '+';
    return `<tr>
      <td>
        <div class="user-name">${t.userName || '—'}</div>
        <div class="user-sub">${t.userPhone || t.userId?.slice(0,8) || ''}</div>
      </td>
      <td class="tx-amount-${t.type || 'credit'}" style="font-size:15px;">${sign}₹${Number(t.amount||0).toLocaleString('en-IN')}</td>
      <td><span class="pill pill-${tc}">${tl}</span></td>
      <td style="font-size:12px;color:var(--text-secondary);">${t.reason || '—'}</td>
      <td style="font-weight:600;">₹${Number(t.balanceAfter||0).toLocaleString('en-IN')}</td>
      <td style="font-size:12px;">${formatDate(t.createdAt)}</td>
    </tr>`;
  }).join('');
}

// Search users for wallet credit
let _walletSearchTimeout = null;
function searchWalletUser() {
  const q = (document.getElementById('credit-user-search')?.value || '').trim().toLowerCase();
  const sugBox = document.getElementById('wallet-user-suggestions');
  clearTimeout(_walletSearchTimeout);
  if (!sugBox) return;
  if (!q) { sugBox.innerHTML = ''; _selectedWalletUser = null; return; }
  _walletSearchTimeout = setTimeout(async () => {
    try {
      const snap = await db.collection('users').orderBy('name').startAt(q).endAt(q + 'ï£¿').limit(8).get();
      if (snap.empty) { sugBox.innerHTML = '<div class="wallet-suggestion-item" style="color:var(--text-muted);">No users found</div>'; return; }
      sugBox.innerHTML = snap.docs.map(doc => {
        const u = doc.data();
        return `<div class="wallet-suggestion-item" onclick="selectWalletUser('${doc.id}','${escHtml(u.name||'')}','${escHtml(u.phone||'')}')">
          <div class="doc-avatar" style="background:#F5E6F0;color:#522546;width:28px;height:28px;font-size:11px;">${getInitials(u.name||'U')}</div>
          <div><div style="font-weight:600;">${escHtml(u.name||'—')}</div><div style="font-size:11px;color:var(--text-muted);">${escHtml(u.phone||u.email||doc.id)}</div></div>
        </div>`;
      }).join('');
    } catch(err) { sugBox.innerHTML = ''; }
  }, 300);
}

function selectWalletUser(uid, name, phone) {
  _selectedWalletUser = { uid, name, phone };
  const selEl = document.getElementById('wallet-selected-user');
  if (selEl) selEl.innerHTML = `<div class="wallet-user-chip"><div><div class="chip-name">${escHtml(name||uid)}</div><div class="chip-sub">${escHtml(phone||uid)}</div></div></div>`;
  const sugBox = document.getElementById('wallet-user-suggestions');
  if (sugBox) sugBox.innerHTML = '';
  const inp = document.getElementById('credit-user-search');
  if (inp) inp.value = name || uid;
}

async function addWalletCredit() {
  if (!_selectedWalletUser) { showToast('Please select a user first'); return; }
  const amount = parseFloat(document.getElementById('credit-amount')?.value || '0');
  const reason = document.getElementById('credit-reason')?.value.trim() || 'Admin credit';
  if (!amount || amount <= 0) { showToast('Enter a valid amount'); return; }

  try {
    // Get current wallet balance
    const userRef  = db.collection('users').doc(_selectedWalletUser.uid);
    const userSnap = await userRef.get();
    const current  = userSnap.data()?.walletBalance || 0;
    const newBal   = current + amount;

    const txData = {
      userId:       _selectedWalletUser.uid,
      userName:     _selectedWalletUser.name,
      userPhone:    _selectedWalletUser.phone,
      amount,
      type:         'credit',
      category:     'admin_credit',
      title:        reason,
      reason,
      balanceAfter: newBal,
      addedBy:      auth.currentUser?.email || 'admin',
      timestamp:    firebase.firestore.FieldValue.serverTimestamp(),
      createdAt:    firebase.firestore.FieldValue.serverTimestamp(),
    };
    const batch = db.batch();
    // Update user wallet balance
    batch.update(userRef, { walletBalance: newBal, updatedAt: firebase.firestore.FieldValue.serverTimestamp() });
    // Write to users/{uid}/transactions (Flutter WalletService reads this)
    const txUserRef = userRef.collection('transactions').doc();
    batch.set(txUserRef, txData);
    // Also write to top-level wallet_transactions for admin view
    const txAdminRef = db.collection('wallet_transactions').doc();
    batch.set(txAdminRef, txData);
    // Add notification for user — correct path: patient_notifications/{uid}/items
    const notifRef = db.collection('patient_notifications').doc(_selectedWalletUser.uid).collection('items').doc();
    batch.set(notifRef, {
      title:     '₹' + amount + ' added to your wallet!',
      body:      reason,
      type:      'wallet',
      isRead:    false,
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      deliverAt: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
    showToast(`₹${amount} credited to ${_selectedWalletUser.name || 'user'} âœ“`);
    // Reset form
    document.getElementById('credit-user-search').value = '';
    document.getElementById('credit-amount').value = '';
    document.getElementById('credit-reason').value = '';
    document.getElementById('wallet-selected-user').innerHTML = 'No user selected';
    _selectedWalletUser = null;
  } catch (err) {
    showToast('Failed: ' + err.message);
  }
}

// ============================================
//   ENHANCED NOTIFICATION CENTER
// ============================================

// Stores all system notifications (all types merged)
let _sysNotifs      = [];
let _sysUnreadCount = 0;
const _seenSysIds   = new Set(JSON.parse(localStorage.getItem('seenSysNotifs') || '[]'));

function addSystemNotif(type, data) {
  const id = `${type}_${data.id}_${Date.now()}`;
  if (_seenSysIds.has(data.id)) return; // Already seen
  const notif = { _id: id, _type: type, _read: false, _ts: Date.now(), ...data };
  _sysNotifs.unshift(notif);
  _sysNotifs = _sysNotifs.slice(0, 50);
  _sysUnreadCount = _sysNotifs.filter(n => !n._read).length;
  updateNotifBadge();
  renderNotifList();
}

function initNotificationsListener() {
  if (_notifUnsubscribe) _notifUnsubscribe();

  // Watch service_requests for new ones
  _notifUnsubscribe = db.collection('service_requests')
    .orderBy('createdAt', 'desc').limit(50)
    .onSnapshot(snap => {
      snap.docChanges().forEach(change => {
        if (change.type === 'added') {
          const d = change.doc.data();
          const id = change.doc.id;
          if (!_seenRequestIds.has(id)) {
            addSvcReqNotif(id, d);
          }
        }
      });
      snap.forEach(doc => {
        const d = doc.data();
        if (!_notifications.find(n => n.id === doc.id)) {
          _notifications.unshift({ id: doc.id, ...d, _read: _seenRequestIds.has(doc.id) });
        }
      });
      _notifications = _notifications.slice(0, 50);
      _unreadNotifCount = _notifications.filter(n => !n._read).length;
      updateNotifBadge();
      renderNotifList();
    }, err => console.error('Notif listener error:', err));
}

function addSvcReqNotif(id, d) {
  const notif = {
    id, ...d,
    _read: false,
    _notifType: 'service_request',
  };
  if (!_notifications.find(n => n.id === id)) {
    _notifications.unshift(notif);
    _unreadNotifCount++;
    updateNotifBadge();
    renderNotifList();
  }
}

function renderNotifList() {
  const list = document.getElementById('notif-list');
  if (!list) return;

  // Merge service request notifs + system notifs
  const merged = [
    ..._sysNotifs.map(n => ({ ...n, _merged: true })),
    ..._notifications.slice(0, 20).map(n => ({ ...n, _merged: false })),
  ]
  .sort((a, b) => (b._ts || 0) - (a._ts || 0))
  .slice(0, 20);

  if (!merged.length) { list.innerHTML = '<div class="notif-empty">No notifications yet</div>'; return; }

  list.innerHTML = merged.map(n => {
    if (n._merged) {
      // System notification (doctor/appointment/ticket)
      const configs = {
        doctor_reg:  { icon: '<i class="ti ti-stethoscope"></i>', bg: '#F5E6F0', fg: '#522546', title: 'New Doctor Registration', sub: escHtml(n.name||'') + ' &ndash; ' + escHtml(n.specialty||'') },
        appointment: { icon: '<i class="ti ti-calendar-check"></i>', bg: '#e8f5e9', fg: '#2e7d32', title: 'New Appointment', sub: escHtml(n.patient||'') + ' with Dr. ' + escHtml(n.doctor||'') },
        ticket:      { icon: '<i class="ti ti-ticket"></i>', bg: '#fff3e0', fg: '#e65100', title: 'New ' + capitalize(n.priority||'medium') + ' Ticket', sub: escHtml(n.user||'') + ': ' + escHtml(n.title||'') },
      };
      const cfg = configs[n._type] || { icon: '<i class="ti ti-bell"></i>', bg: '#f3e5f5', fg: '#7b1fa2', title: 'System Notification', sub: '' };
      return `<div class="notif-item ${!n._read ? 'notif-unread' : ''}" onclick="handleSysNotifClick('${n._id}','${n._type}','${n.id||''}')">
        <div class="notif-icon" style="background:${cfg.bg};color:${cfg.fg};">${cfg.icon}</div>
        <div class="notif-content">
          <div class="notif-title">${cfg.title}</div>
          <div class="notif-sub">${cfg.sub}</div>
          <div class="notif-time">${timeAgo({ toDate: () => new Date(n._ts) })}</div>
        </div>
        ${!n._read ? '<div class="notif-dot"></div>' : ''}
      </div>`;
    } else {
      // Service request notification
      const tc    = reqTypeColor(n.type);
      const icon  = reqTypeIcon(n.type);
      const label = reqTypeLabel(n.type);
      const time  = n.createdAt ? timeAgo(n.createdAt) : '';
      const isUnread = !n._read;
      return `<div class="notif-item ${isUnread ? 'notif-unread' : ''}" onclick="openRequestFromNotif('${n.id}')">
        <div class="notif-icon" style="background:${tc.bg};color:${tc.fg};">${icon}</div>
        <div class="notif-content">
          <div class="notif-title">New ${label} Request</div>
          <div class="notif-sub">${escHtml(n.patientName||'Patient')} &middot; ${escHtml(n.serviceName||label)}</div>
          <div class="notif-time">${time}</div>
        </div>
        ${isUnread ? '<div class="notif-dot"></div>' : ''}
      </div>`;
    }
  }).join('');
}

function handleSysNotifClick(nId, type, docId) {
  const n = _sysNotifs.find(x => x._id === nId);
  if (n) { n._read = true; _seenSysIds.add(docId); }
  localStorage.setItem('seenSysNotifs', JSON.stringify([..._seenSysIds]));
  _sysUnreadCount = _sysNotifs.filter(x => !x._read).length;
  _unreadNotifCount = _notifications.filter(n => !n._read).length + _sysUnreadCount;
  updateNotifBadge();
  document.getElementById('notif-panel').style.display = 'none';
  const tabMap = { doctor_reg: 'doctors', appointment: 'appointments', ticket: 'tickets' };
  if (tabMap[type]) switchTab(tabMap[type], { doctors:'Doctors', appointments:'Appointments', tickets:'Support Tickets' }[type]);
}

function updateNotifBadge() {
  const badge = document.getElementById('notif-badge');
  if (!badge) return;
  const total = _unreadNotifCount + _sysUnreadCount;
  if (total > 0) { badge.textContent = total > 99 ? '99+' : total; badge.style.display = 'flex'; }
  else badge.style.display = 'none';
}

function markAllNotifsRead() {
  _notifications.forEach(n => { n._read = true; _seenRequestIds.add(n.id); });
  _sysNotifs.forEach(n => { n._read = true; if (n.id) _seenSysIds.add(n.id); });
  localStorage.setItem('seenRequests', JSON.stringify([..._seenRequestIds]));
  localStorage.setItem('seenSysNotifs', JSON.stringify([..._seenSysIds]));
  _unreadNotifCount = 0;
  _sysUnreadCount   = 0;
  updateNotifBadge();
  renderNotifList();
}

// ============================================
//   BROADCAST NOTIFICATIONS
// ============================================

function toggleSpecificUser() {
  const target = document.getElementById('notif-target')?.value;
  const row    = document.getElementById('specific-user-row');
  if (row) row.style.display = target === 'specific_user' ? 'block' : 'none';
}

async function sendBroadcast() {
  const target  = document.getElementById('notif-target')?.value;
  const type    = document.getElementById('notif-type')?.value;
  const title   = document.getElementById('notif-title')?.value.trim();
  const body    = document.getElementById('notif-body')?.value.trim();
  const link    = document.getElementById('notif-link')?.value.trim();
  const userId  = document.getElementById('notif-user-id')?.value.trim();

  if (!title) { showToast('Notification title is required'); return; }
  if (!body)  { showToast('Notification message is required'); return; }
  if (target === 'specific_user' && !userId) { showToast('Enter a user ID or phone'); return; }

  const iconMap = { general:'', offer:'', alert:'âš ï¸', update:'', emergency:'' };

  const broadcastDoc = {
    target, type, title, body,
    link:        link || null,
    icon:        iconMap[type] || '',
    sentBy:      auth.currentUser?.email || 'admin',
    sentAt:      firebase.firestore.FieldValue.serverTimestamp(),
    targetUserId: target === 'specific_user' ? userId : null,
    status:       'sent',
  };

  try {
    // Save to broadcasts collection (Cloud Functions / FCM handler can pick this up)
    await db.collection('broadcasts').add(broadcastDoc);

    const now = firebase.firestore.FieldValue.serverTimestamp();
    const notifData = { title, body, type, link: link||null, isRead: false, createdAt: now, deliverAt: now };

    // Write to patient_notifications/{uid}/items  (correct path Flutter reads from)
    if (target === 'all_patients' || target === 'all_users') {
      const usersSnap = await db.collection('users').limit(500).get();
      const batch = db.batch();
      usersSnap.docs.forEach(doc => {
        const notifRef = db.collection('patient_notifications').doc(doc.id).collection('items').doc();
        batch.set(notifRef, notifData);
      });
      await batch.commit();
    }

    // Write to doctor_notifications/{uid}/items  (correct path Doctor app reads from)
    if (target === 'all_doctors' || target === 'all_users') {
      const docsSnap = await db.collection('doctors').where('status', '==', 'active').limit(200).get();
      const batch = db.batch();
      docsSnap.docs.forEach(doc => {
        const notifRef = db.collection('doctor_notifications').doc(doc.id).collection('items').doc();
        batch.set(notifRef, { title, body, type, link: link||null, isRead: false, createdAt: now });
      });
      await batch.commit();
    }

    // Specific user — write to correct path
    if (target === 'specific_user' && userId) {
      await db.collection('patient_notifications').doc(userId).collection('items').add({
        ...notifData,
      });
    }

    showToast(`Notification sent to ${target.replace('_',' ')} âœ“`);
    // Reset form
    ['notif-title','notif-body','notif-link','notif-user-id'].forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
    loadBroadcasts();
  } catch (err) {
    showToast('Send failed: ' + err.message);
  }
}

async function loadBroadcasts() {
  const el = document.getElementById('broadcasts-list');
  if (!el) return;
  try {
    const snap = await db.collection('broadcasts').orderBy('sentAt', 'desc').limit(20).get();
    if (snap.empty) { el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-speakerphone"></i></div><p>No broadcasts sent yet</p></div>'; return; }
    const iconMap = { general:'', offer:'', alert:'âš ï¸', update:'', emergency:'' };
    const tgLabel = { all_patients:'All Patients', all_doctors:'All Doctors', all_users:'Everyone', specific_user:'Specific User' };
    el.innerHTML = snap.docs.map(doc => {
      const b = doc.data();
      return `<div class="broadcast-item">
        <div class="broadcast-icon" style="background:${b.type==='emergency'?'#FFEBEE':'#F5E6F0'};color:${b.type==='emergency'?'#C62828':'#522546'};">${iconMap[b.type]||''}</div>
        <div class="broadcast-content">
          <div class="broadcast-title">${escHtml(b.title||'—')}</div>
          <div class="broadcast-sub">${escHtml(b.body||'')}</div>
          <div class="broadcast-meta">â†’ ${tgLabel[b.target]||b.target} · ${formatDate(b.sentAt)} · by ${escHtml(b.sentBy||'admin')}</div>
        </div>
      </div>`;
    }).join('');
  } catch(err) { el.innerHTML = '<div class="empty-state"><p>Could not load broadcasts</p></div>'; }
}

// ============================================
//   MATERNITY CARE MANAGEMENT
// ============================================

let _matProfiles = [];
let _currentAssignProfileId = '';

function initMaternityListeners() {
  // Real-time listener for unresolved alerts
  db.collection('pregnancy_alerts')
    .where('isResolved', '==', false)
    .onSnapshot(snap => {
      const count = snap.size;
      const badge = document.getElementById('nav-maternity-alerts');
      if (badge) {
        if (count > 0) { badge.textContent = count; badge.style.display = ''; }
        else badge.style.display = 'none';
      }
      const alertCount = document.getElementById('mat-alerts');
      if (alertCount) alertCount.textContent = count;
    });
}

async function loadMaternityOverview() {
  try {
    const [profilesSnap, alertsSnap, checkupsSnap] = await Promise.all([
      db.collection('pregnancy_profiles').where('isActive', '==', true).get(),
      db.collection('pregnancy_alerts').where('isResolved', '==', false).get(),
      db.collection('pregnancy_checkups')
        .where('status', '==', 'upcoming')
        .where('scheduledDate', '>=', new Date())
        .get()
    ]);
    document.getElementById('mat-total').textContent = profilesSnap.size;
    const highRisk = profilesSnap.docs.filter(d => d.data().isHighRisk).length;
    document.getElementById('mat-highrisk').textContent = highRisk;
    document.getElementById('mat-alerts').textContent = alertsSnap.size;
    document.getElementById('mat-checkups').textContent = checkupsSnap.size;

    _matProfiles = profilesSnap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderMaternityPatients(_matProfiles);
    loadMaternityAlerts();
  } catch(e) { console.error('loadMaternityOverview', e); }
}

async function loadMaternityAlerts() {
  const tbody = document.getElementById('mat-alerts-body');
  if (!tbody) return;
  try {
    const snap = await db.collection('pregnancy_alerts')
      .where('isResolved', '==', false)
      .orderBy('reportedAt', 'desc')
      .limit(20)
      .get();
    if (snap.empty) {
      tbody.innerHTML = '<tr><td colspan="6" class="empty-row">No active alerts ';
      return;
    }
    tbody.innerHTML = snap.docs.map(doc => {
      const a = doc.data();
      const reportedAt = a.reportedAt?.toDate ? a.reportedAt.toDate() : new Date();
      const sevClass = a.severity === 'critical' ? 'color:#b71c1c;font-weight:700;'
        : a.severity === 'high' ? 'color:#e65100;font-weight:700;' : 'color:#f57f17;';
      return `<tr>
        <td><strong>${escHtml(a.patientName||'—')}</strong></td>
        <td>${escHtml((a.type||'').replace(/_/g,' ').toUpperCase())}</td>
        <td style="${sevClass}">${(a.severity||'').toUpperCase()}</td>
        <td style="max-width:220px;white-space:normal;">${escHtml(a.message||'')}</td>
        <td>${formatDate(a.reportedAt)}</td>
        <td>
          <button class="btn-outline" style="padding:4px 10px;font-size:11px;color:#2e7d32;border-color:#2e7d32;"
            onclick="resolveAlert('${doc.id}')">Resolve</button>
        </td>
      </tr>`;
    }).join('');
  } catch(e) {
    tbody.innerHTML = '<tr><td colspan="6" class="empty-row">Error loading alerts</td></tr>';
  }
}

async function resolveAlert(alertId) {
  if (!confirm('Mark this alert as resolved?')) return;
  try {
    await db.collection('pregnancy_alerts').doc(alertId).update({
      isResolved: true,
      resolvedBy: 'admin',
      resolvedAt: firebase.firestore.FieldValue.serverTimestamp()
    });
    showToast('Alert resolved');
    loadMaternityAlerts();
  } catch(e) { showToast('Error: ' + e.message); }
}

function renderMaternityPatients(profiles) {
  const tbody = document.getElementById('mat-patients-body');
  if (!tbody) return;
  if (!profiles.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="empty-row">No active pregnancy profiles</td></tr>';
    return;
  }
  tbody.innerHTML = profiles.map(p => {
    const lmp = p.lmpDate?.toDate ? p.lmpDate.toDate() : new Date();
    const days = Math.floor((Date.now() - lmp.getTime()) / 86400000);
    const week = Math.min(42, Math.max(1, Math.floor(days / 7)));
    const trimester = week <= 13 ? '1st' : week <= 26 ? '2nd' : '3rd';
    const due = p.dueDate?.toDate ? p.dueDate.toDate() : new Date();
    const riskBadge = p.isHighRisk
      ? '<span style="background:#ffebee;color:#b71c1c;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:700;">HIGH RISK</span>'
      : '<span style="background:#e8f5e9;color:#2e7d32;padding:2px 8px;border-radius:10px;font-size:10px;">NORMAL</span>';
    return `<tr>
      <td><strong>${escHtml(p.patientName||p.patientId||'Patient')}</strong></td>
      <td>Week ${week}</td>
      <td>${trimester}</td>
      <td>${due.toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'})}</td>
      <td>${escHtml(p.assignedDoctorName||'—')}</td>
      <td>${riskBadge}</td>
      <td>
        <button class="btn-outline" style="padding:4px 10px;font-size:11px;"
          onclick="openAssignDoctorModal('${p.id}','${escHtml(p.patientName||p.patientId||'Patient')}')">
          Assign Doctor
        </button>
        ${p.isHighRisk ? '' : `<button class="btn-outline" style="padding:4px 10px;font-size:11px;color:#e65100;border-color:#e65100;margin-left:4px;"
          onclick="flagHighRisk('${p.id}')">Flag Risk</button>`}
      </td>
    </tr>`;
  }).join('');
}

function filterMaternityPatients() {
  const search = (document.getElementById('mat-search')?.value || '').toLowerCase();
  const risk = document.getElementById('mat-filter-risk')?.value || 'all';
  const filtered = _matProfiles.filter(p => {
    const name = ((p.patientName || '') + ' ' + (p.patientId || '')).toLowerCase();
    const matchSearch = !search || name.includes(search);
    const matchRisk = risk === 'all' || (risk === 'high' && p.isHighRisk) || (risk === 'normal' && !p.isHighRisk);
    return matchSearch && matchRisk;
  });
  renderMaternityPatients(filtered);
}

async function openAssignDoctorModal(profileId, patientName) {
  _currentAssignProfileId = profileId;
  document.getElementById('assign-patient-name').textContent = 'Patient: ' + patientName;
  const modal = document.getElementById('assign-doctor-modal');
  if (modal) modal.style.display = 'flex';

  const select = document.getElementById('assign-doctor-select');
  select.innerHTML = '<option value="">Loading doctors...</option>';
  try {
    const snap = await db.collection('doctors').where('status', '==', 'active').get();
    select.innerHTML = '<option value="">Select a doctor</option>' +
      snap.docs.map(d => {
        const doc = d.data();
        return `<option value="${d.id}" data-name="${escHtml(doc.name||'Dr.')}">${escHtml(doc.name||'Doctor')} — ${escHtml(doc.specialty||'')}</option>`;
      }).join('');
  } catch(e) {
    select.innerHTML = '<option value="">Error loading doctors</option>';
  }
}

async function confirmAssignDoctor() {
  const select = document.getElementById('assign-doctor-select');
  const doctorId = select.value;
  if (!doctorId) { showToast('Please select a doctor'); return; }
  const doctorName = select.options[select.selectedIndex]?.getAttribute('data-name') || 'Doctor';
  try {
    await db.collection('pregnancy_profiles').doc(_currentAssignProfileId).update({
      assignedDoctorId: doctorId,
      assignedDoctorName: doctorName,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    });
    document.getElementById('assign-doctor-modal').style.display = 'none';
    showToast('Doctor assigned successfully');
    loadMaternityOverview();
  } catch(e) { showToast('Error: ' + e.message); }
}

async function flagHighRisk(profileId) {
  if (!confirm('Flag this patient as High Risk? This will enable priority monitoring.')) return;
  try {
    await db.collection('pregnancy_profiles').doc(profileId).update({
      isHighRisk: true,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    });
    showToast('Patient flagged as high risk');
    loadMaternityOverview();
  } catch(e) { showToast('Error: ' + e.message); }
}

// Load maternity when tab is opened
const _origSwitchTab = window.switchTab;
window.switchTab = function(tab, title) {
  _origSwitchTab && _origSwitchTab(tab, title);
  if (tab === 'maternity') loadMaternityOverview();
  if (tab === 'reviews')   loadReviews();
};

// ============================================
//   DOCTOR REVIEWS
// ============================================

let _allReviews = [];

async function loadReviews() {
  try {
    // Load all reviews ordered by newest first
    const snap = await db.collection('doctor_reviews')
      .orderBy('createdAt', 'desc')
      .limit(200)
      .get();

    _allReviews = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));

    // Compute stats
    const total = _allReviews.length;
    const flagged = _allReviews.filter(r => r.isFlagged).length;
    const verified = _allReviews.filter(r => r.isVerified !== false).length;
    const avgRating = total > 0
      ? (_allReviews.reduce((s, r) => s + (r.rating || 0), 0) / total).toFixed(1)
      : '—';

    document.getElementById('stat-total-reviews').textContent   = total.toLocaleString();
    document.getElementById('stat-avg-rating').textContent      = total > 0 ? `${avgRating} â­` : '—';
    document.getElementById('stat-flagged-reviews').textContent = flagged;
    document.getElementById('stat-verified-reviews').textContent = verified.toLocaleString();

    // Update nav badge if flagged reviews exist
    const badge = document.getElementById('nav-reviews-flagged');
    if (flagged > 0) {
      badge.textContent = flagged;
      badge.style.display = 'inline-flex';
    } else {
      badge.style.display = 'none';
    }

    applyReviewsFilter();
  } catch (err) {
    console.error('Reviews load error:', err);
  }
}

function applyReviewsFilter() {
  const statusFilter = document.getElementById('reviews-filter-status')?.value || 'all';
  const ratingFilter = document.getElementById('reviews-filter-rating')?.value || 'all';
  const searchVal    = (document.getElementById('reviews-search')?.value || '').toLowerCase();

  let filtered = [..._allReviews];

  if (statusFilter === 'flagged') filtered = filtered.filter(r => r.isFlagged);
  if (statusFilter === 'clean')   filtered = filtered.filter(r => !r.isFlagged);
  if (ratingFilter !== 'all')     filtered = filtered.filter(r => Math.round(r.rating || 0) === parseInt(ratingFilter));
  if (searchVal) {
    filtered = filtered.filter(r =>
      (r.patientName  || '').toLowerCase().includes(searchVal) ||
      (r.doctorId     || '').toLowerCase().includes(searchVal) ||
      (r.reviewText   || '').toLowerCase().includes(searchVal)
    );
  }

  renderReviewsTable(filtered);
}

function renderReviewsTable(reviews) {
  const tbody = document.getElementById('reviews-tbody');
  if (!reviews.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="loading">No reviews found</td></tr>';
    return;
  }

  tbody.innerHTML = reviews.map(r => {
    const stars = 'â­'.repeat(Math.round(r.rating || 0));
    const ratingNum = (r.rating || 0).toFixed(1);
    const date = r.createdAt?.toDate ? r.createdAt.toDate().toLocaleDateString('en-IN') : '—';
    const text = (r.reviewText || '').slice(0, 80) + ((r.reviewText || '').length > 80 ? '...' : '');
    const flagPill = r.isFlagged
      ? '<span class="pill" style="background:#FFEBEE;color:#C62828;">Flagged</span>'
      : '<span class="pill" style="background:#E8F5E9;color:#2E7D32;">Clean</span>';

    return `<tr>
      <td><div class="user-name">${r.patientName || '—'}</div></td>
      <td><div class="user-sub" style="font-size:12px;">${r.doctorId || '—'}</div></td>
      <td><span title="${ratingNum}">${stars} ${ratingNum}</span></td>
      <td><span title="${r.reviewText || ''}">${text || '<em style="color:#9E9E9E;">No text</em>'}</span></td>
      <td>${r.consultationType || '—'}</td>
      <td>${date}</td>
      <td>${flagPill}</td>
      <td>
        ${!r.isFlagged
          ? `<button class="btn btn-outline" style="color:#E65100;border-color:#E65100;" onclick="flagReview('${r.id}', this)">
               <i class="ti ti-flag"></i> Flag
             </button>`
          : `<button class="btn btn-approve" onclick="unflagReview('${r.id}', this)">
               <i class="ti ti-flag-off"></i> Unflag
             </button>`
        }
        <button class="btn btn-reject" style="margin-left:4px;" onclick="deleteReview('${r.id}', this)">
          <i class="ti ti-trash"></i> Remove
        </button>
      </td>
    </tr>`;
  }).join('');
}

async function flagReview(reviewId, btn) {
  if (!confirm('Flag this review as policy violation? It will be hidden from patients.')) return;
  btn.disabled = true;
  try {
    await db.collection('doctor_reviews').doc(reviewId).update({ isFlagged: true });
    showToast('Review flagged and hidden from patients.');
    loadReviews();
  } catch (e) {
    showToast('Error: ' + e.message);
    btn.disabled = false;
  }
}

async function unflagReview(reviewId, btn) {
  btn.disabled = true;
  try {
    await db.collection('doctor_reviews').doc(reviewId).update({ isFlagged: false });
    showToast('Review unflagged and restored.');
    loadReviews();
  } catch (e) {
    showToast('Error: ' + e.message);
    btn.disabled = false;
  }
}

async function deleteReview(reviewId, btn) {
  if (!confirm('Permanently delete this review? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    // Get review data first to update the rating summary
    const reviewDoc = await db.collection('doctor_reviews').doc(reviewId).get();
    if (!reviewDoc.exists) {
      showToast('Review not found.');
      return;
    }
    const review = reviewDoc.data();

    // Delete the review document
    await db.collection('doctor_reviews').doc(reviewId).delete();

    // Remove the appointment_reviews lock so patient can re-review if needed
    if (review.appointmentId) {
      await db.collection('appointment_reviews').doc(review.appointmentId).delete();
    }

    // Recalculate doctor rating summary from remaining reviews
    if (review.doctorId) {
      const remainingSnap = await db.collection('doctor_reviews')
        .where('doctorId', '==', review.doctorId)
        .where('isFlagged', '==', false)
        .get();

      const remaining = remainingSnap.docs.map(d => d.data());
      const newTotal = remaining.length;
      const newAvg = newTotal > 0
        ? remaining.reduce((s, r) => s + (r.rating || 0), 0) / newTotal
        : 0;

      const dist = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
      remaining.forEach(r => {
        const bucket = Math.round(r.rating || 0);
        if (bucket >= 1 && bucket <= 5) dist[bucket]++;
      });

      await db.collection('doctor_rating_summary').doc(review.doctorId).set({
        averageRating: parseFloat(newAvg.toFixed(2)),
        totalReviews: newTotal,
        ratingDistribution: dist,
        lastUpdated: firebase.firestore.FieldValue.serverTimestamp(),
      });

      // Mirror to doctors document
      await db.collection('doctors').doc(review.doctorId).update({
        rating: parseFloat(newAvg.toFixed(2)),
        totalReviews: newTotal,
      });
    }

    showToast('Review permanently deleted and ratings recalculated.');
    loadReviews();
  } catch (e) {
    showToast('Error: ' + e.message);
    btn.disabled = false;
  }
}

// ============================================
//   WEEKLY QUALITY ANALYTICS
// ============================================

let _qualityReports = [];
let _activeQualityReport = null;
let _qaRatingChart = null;
let _qaTrendChart = null;
let _qaAllDoctors = [];

async function loadQualityAnalytics() {
  try {
    const snap = await db.collection('weekly_quality_reports')
      .orderBy('generatedAt', 'desc')
      .limit(12)
      .get();

    _qualityReports = snap.docs.map(d => ({ id: d.id, ...d.data() }));

    const picker = document.getElementById('quality-week-picker');
    if (!picker) return;

    if (_qualityReports.length === 0) {
      picker.innerHTML = '<option value="">No reports yet — click Generate Now</option>';
      renderEmptyQualityState();
      return;
    }

    picker.innerHTML = _qualityReports.map((r, i) => {
      const label = formatQualityReportLabel(r);
      return '<option value="' + i + '"' + (i === 0 ? ' selected' : '') + '>' + label + '</option>';
    }).join('');

    renderQualityReport(_qualityReports[0]);
    buildQualityTrendChart(_qualityReports);
  } catch (e) {
    console.error('loadQualityAnalytics error:', e);
  }
}

function formatQualityReportLabel(report) {
  const by = report.generatedBy === 'manual' ? ' (manual)' : '';
  if (report.weekStart && report.weekStart.toDate) {
    const ws = report.weekStart.toDate();
    const we = report.weekEnd ? report.weekEnd.toDate() : new Date(ws.getTime() + 6 * 86400000);
    const fmt = d => d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
    return (report.reportId || '') + ' · ' + fmt(ws) + ' — ' + fmt(we) + by;
  }
  return report.reportId || report.id;
}

function onQualityWeekChange() {
  const picker = document.getElementById('quality-week-picker');
  if (!picker) return;
  const idx = parseInt(picker.value, 10);
  if (!isNaN(idx) && _qualityReports[idx]) {
    renderQualityReport(_qualityReports[idx]);
  }
}

function renderQualityReport(report) {
  _activeQualityReport = report;
  const ps = report.platformStats || {};

  const setText = (id, val) => {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  };

  setText('qa-avg-rating',     ps.avgRating != null ? ps.avgRating.toFixed(2) : '—');
  setText('qa-satisfaction',   ps.satisfactionPercent != null ? ps.satisfactionPercent + '%' : '—');
  setText('qa-poor-pct',       ps.poorConsultationPercent != null ? ps.poorConsultationPercent + '%' : '—');
  setText('qa-flagged',        ps.flaggedDoctorsCount != null ? ps.flaggedDoctorsCount : '—');
  setText('qa-total-feedback', ps.totalFeedback != null ? ps.totalFeedback.toLocaleString() : '—');
  setText('qa-total-appts',    ps.totalAppointments != null ? ps.totalAppointments.toLocaleString() : '—');
  setText('qa-cancelled',      ps.totalCancelled != null ? ps.totalCancelled.toLocaleString() : '—');
  setText('qa-missed',         ps.totalMissed != null ? ps.totalMissed.toLocaleString() : '—');

  const badge = document.getElementById('nav-quality-flagged');
  if (badge) {
    const flagged = ps.flaggedDoctorsCount || 0;
    badge.textContent = flagged;
    badge.style.display = flagged > 0 ? 'flex' : 'none';
  }

  buildQualityRatingDistChart(report.ratingDistribution || {});
  renderQualityTopPerformers(report.topPerformers || []);
  renderQualityLowPerformers(report.lowPerformers || []);

  _qaAllDoctors = Object.values(report.doctorStats || {});
  filterQualityDoctors();
}

function buildQualityRatingDistChart(dist) {
  const ctx = document.getElementById('qa-rating-dist-chart');
  if (!ctx) return;

  const labels = ['1 Star', '2 Stars', '3 Stars', '4 Stars', '5 Stars'];
  const values = [dist['1'] || 0, dist['2'] || 0, dist['3'] || 0, dist['4'] || 0, dist['5'] || 0];
  const colors = ['#ef5350', '#ff7043', '#ffca28', '#66bb6a', '#42a5f5'];

  if (_qaRatingChart) { _qaRatingChart.destroy(); _qaRatingChart = null; }

  _qaRatingChart = new Chart(ctx, {
    type: 'doughnut',
    data: { labels, datasets: [{ data: values, backgroundColor: colors, borderWidth: 2, borderColor: '#fff' }] },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: '62%',
      plugins: {
        legend: { position: 'right', labels: { font: { size: 12 }, padding: 10, boxWidth: 14 } },
        tooltip: { callbacks: { label: ctx => ' ' + ctx.label + ': ' + ctx.parsed + ' reviews' } },
      },
    },
  });
}

function buildQualityTrendChart(reports) {
  const ctx = document.getElementById('qa-trend-chart');
  if (!ctx) return;

  const sorted = [...reports].reverse();
  const labels = sorted.map(r => {
    if (r.weekStart && r.weekStart.toDate) {
      return r.weekStart.toDate().toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
    }
    return r.reportId || '';
  });

  const avgRatings    = sorted.map(r => (r.platformStats && r.platformStats.avgRating != null) ? r.platformStats.avgRating : null);
  const satisfactions = sorted.map(r => (r.platformStats && r.platformStats.satisfactionPercent != null) ? r.platformStats.satisfactionPercent : null);

  if (_qaTrendChart) { _qaTrendChart.destroy(); _qaTrendChart = null; }

  _qaTrendChart = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [
        { label: 'Avg Rating', data: avgRatings, borderColor: '#1a73e8', backgroundColor: 'rgba(26,115,232,0.08)', tension: 0.35, fill: true, pointRadius: 4, yAxisID: 'y' },
        { label: 'Satisfaction %', data: satisfactions, borderColor: '#2e7d32', backgroundColor: 'rgba(46,125,50,0.06)', tension: 0.35, fill: false, borderDash: [5, 3], pointRadius: 3, yAxisID: 'y1' },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: { legend: { position: 'top', labels: { font: { size: 12 } } } },
      scales: {
        y:  { position: 'left',  min: 0, max: 5,   title: { display: true, text: 'Avg Rating' } },
        y1: { position: 'right', min: 0, max: 100, grid: { drawOnChartArea: false }, title: { display: true, text: 'Satisfaction %' } },
      },
    },
  });
}

function renderQualityTopPerformers(doctors) {
  const tbody = document.getElementById('qa-top-performers-tbody');
  if (!tbody) return;

  if (!doctors.length) {
    tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:20px;">No top performers this week — data populates once ratings are submitted</td></tr>';
    return;
  }

  tbody.innerHTML = doctors.map((d, i) => {
    const stars  = renderQualityStarBadge(d.avgRating);
    const sat    = d.satisfactionPercent != null ? d.satisfactionPercent + '%' : '—';
    const feed   = d.feedbackCount || 0;
    const cancel = d.cancellationPercent != null ? d.cancellationPercent + '%' : '—';
    const medal  = i === 0 ? '' : i === 1 ? '' : i === 2 ? '' : '#' + (i + 1);
    return '<tr>'
      + '<td style="font-weight:700;">' + medal + '</td>'
      + '<td>' + escHtml(d.doctorName || '—') + '</td>'
      + '<td style="color:var(--text-secondary);font-size:12px;">' + escHtml(d.specialty || '—') + '</td>'
      + '<td>' + stars + '</td>'
      + '<td><span style="background:#e8f5e9;color:#2e7d32;padding:2px 8px;border-radius:20px;font-size:12px;font-weight:600;">' + sat + '</span></td>'
      + '<td style="text-align:center;">' + feed + '</td>'
      + '<td>' + cancel + '</td>'
      + '</tr>';
  }).join('');
}

function renderQualityLowPerformers(doctors) {
  const tbody = document.getElementById('qa-low-performers-tbody');
  if (!tbody) return;

  if (!doctors.length) {
    tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:20px;">No flagged doctors this week</td></tr>';
    return;
  }

  tbody.innerHTML = doctors.map(d => {
    const stars  = d.avgRating != null ? renderQualityStarBadge(d.avgRating) : '—';
    const sat    = d.satisfactionPercent != null ? d.satisfactionPercent + '%' : '—';
    const poor   = d.poorPercent != null ? d.poorPercent + '%' : '—';
    const cancel = d.cancellationPercent != null ? d.cancellationPercent + '%' : '—';
    const reasons = (d.flagReasons || []).map(r =>
      '<span style="background:#fce8e6;color:#c62828;padding:2px 7px;border-radius:20px;font-size:11px;margin:2px;display:inline-block;">' + escHtml(r) + '</span>'
    ).join('');
    return '<tr>'
      + '<td>' + escHtml(d.doctorName || '—') + '</td>'
      + '<td style="color:var(--text-secondary);font-size:12px;">' + escHtml(d.specialty || '—') + '</td>'
      + '<td>' + stars + '</td>'
      + '<td><span style="background:#fce8e6;color:#c62828;padding:2px 8px;border-radius:20px;font-size:12px;font-weight:600;">' + sat + '</span></td>'
      + '<td>' + poor + '</td>'
      + '<td>' + cancel + '</td>'
      + '<td>' + (reasons || '—') + '</td>'
      + '</tr>';
  }).join('');
}

function filterQualityDoctors() {
  const searchEl = document.getElementById('qa-doctor-search');
  const sortEl   = document.getElementById('qa-sort');
  const tbody    = document.getElementById('qa-all-doctors-tbody');
  if (!tbody) return;

  const search  = searchEl ? searchEl.value.toLowerCase() : '';
  const sortVal = sortEl ? sortEl.value : 'rating-desc';

  let list = _qaAllDoctors.filter(d => {
    if (!search) return true;
    return (d.doctorName || '').toLowerCase().includes(search) ||
           (d.specialty || '').toLowerCase().includes(search);
  });

  list.sort((a, b) => {
    if (sortVal === 'rating-desc')       return (b.avgRating || 0) - (a.avgRating || 0);
    if (sortVal === 'rating-asc')        return (a.avgRating || 99) - (b.avgRating || 99);
    if (sortVal === 'satisfaction-desc') return (b.satisfactionPercent || 0) - (a.satisfactionPercent || 0);
    if (sortVal === 'feedback-desc')     return (b.feedbackCount || 0) - (a.feedbackCount || 0);
    return 0;
  });

  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="10" style="text-align:center;color:var(--text-muted);padding:20px;">No doctor data for this period</td></tr>';
    return;
  }

  tbody.innerHTML = list.map(d => {
    const stars  = d.avgRating != null ? renderQualityStarBadge(d.avgRating) : '<span style="color:var(--text-muted);">No ratings</span>';
    const sat    = d.satisfactionPercent != null ? d.satisfactionPercent + '%' : '—';
    const poor   = d.poorPercent != null ? d.poorPercent + '%' : '—';
    const cancel = d.cancellationPercent != null ? d.cancellationPercent + '%' : '—';
    const missed = d.missedAppointments != null ? d.missedAppointments : '—';
    const statusBadge = d.isFlagged
      ? '<span style="background:#fce8e6;color:#c62828;padding:2px 8px;border-radius:20px;font-size:11px;font-weight:600;">Flagged</span>'
      : '<span style="background:#e8f5e9;color:#2e7d32;padding:2px 8px;border-radius:20px;font-size:11px;font-weight:600;">Good</span>';
    return '<tr>'
      + '<td>' + escHtml(d.doctorName || '—') + '</td>'
      + '<td style="color:var(--text-secondary);font-size:12px;">' + escHtml(d.specialty || '—') + '</td>'
      + '<td style="text-align:center;">' + (d.feedbackCount || 0) + '</td>'
      + '<td>' + stars + '</td>'
      + '<td>' + sat + '</td>'
      + '<td style="color:' + (d.poorPercent > 30 ? '#c62828' : 'inherit') + '">' + poor + '</td>'
      + '<td style="text-align:center;">' + (d.totalAppointments || 0) + '</td>'
      + '<td style="color:' + (d.cancellationPercent > 40 ? '#c62828' : 'inherit') + '">' + cancel + '</td>'
      + '<td style="color:' + (d.missedAppointments > 3 ? '#c62828' : 'inherit') + ';text-align:center;">' + missed + '</td>'
      + '<td>' + statusBadge + '</td>'
      + '</tr>';
  }).join('');
}

function renderQualityStarBadge(rating) {
  if (rating == null) return '—';
  const rounded = Math.round(rating * 2) / 2;
  let stars = '';
  for (let i = 1; i <= 5; i++) {
    if (i <= Math.floor(rounded)) {
      stars += '<i class="ti ti-star-filled" style="color:#f9a825;font-size:13px;"></i>';
    } else if (i - 0.5 === rounded) {
      stars += '<i class="ti ti-star-half-filled" style="color:#f9a825;font-size:13px;"></i>';
    } else {
      stars += '<i class="ti ti-star" style="color:#e0e0e0;font-size:13px;"></i>';
    }
  }
  return '<span style="display:inline-flex;align-items:center;gap:1px;">' + stars
    + ' <span style="font-size:12px;font-weight:700;margin-left:4px;color:var(--text-primary);">'
    + rating.toFixed(1) + '</span></span>';
}

function renderEmptyQualityState() {
  const msg = '<tr><td colspan="10" style="text-align:center;color:var(--text-muted);padding:24px;">No reports yet. Click <strong>Generate Now</strong> to create the first report.</td></tr>';
  ['qa-top-performers-tbody', 'qa-low-performers-tbody', 'qa-all-doctors-tbody'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = msg;
  });
}

async function generateQualityReportNow() {
  const btn = document.getElementById('gen-report-btn');
  if (!btn) return;
  const orig = btn.innerHTML;
  btn.innerHTML = '<i class="ti ti-loader"></i> Generating…';
  btn.disabled = true;

  try {
    await db.collection('report_triggers').add({
      type: 'weekly_quality',
      requestedAt: firebase.firestore.FieldValue.serverTimestamp(),
      requestedBy: (auth.currentUser && auth.currentUser.uid) || 'admin',
      status: 'pending',
    });
    showToast('Report generation triggered — it will appear in the list within a minute.');
    setTimeout(() => loadQualityAnalytics(), 10000);
  } catch (e) {
    showToast('Error triggering report: ' + e.message);
  } finally {
    btn.innerHTML = orig;
    btn.disabled = false;
  }
}

// ============================================
//   NUTRITION MANAGEMENT
// ============================================

let _nutrNutritionists = [];   // cache for client-side search/filter
let _nutrApptUnsub = null;     // realtime listener for appointments

// Called when admin switches to the Nutrition tab
function initNutritionTab() {
  loadNutritionStats();
  loadNutritionistsList();
  loadNutritionAppointments();
  loadMealLogs();
  loadNutritionGoals();
  loadDietPlans();

  // Default the date picker to today
  const dp = document.getElementById('nutr-meal-date');
  if (dp && !dp.value) {
    const today = new Date();
    dp.value = today.toISOString().slice(0, 10);
  }
}

// ── Analytics counters ──────────────────────────────────────────────────────

async function loadNutritionStats() {
  try {
    const [nSnap, aSnap, pendSnap, goalSnap] = await Promise.all([
      db.collection('nutritionists').get(),
      db.collection('nutrition_appointments').get(),
      db.collection('nutrition_appointments').where('status', '==', 'pending').get(),
      db.collection('nutrition_goals').where('isActive', '==', true).get(),
    ]);
    document.getElementById('nutr-stat-nutritionists').textContent = nSnap.size;
    document.getElementById('nutr-stat-appts').textContent = aSnap.size;
    document.getElementById('nutr-stat-pending').textContent = pendSnap.size;
    document.getElementById('nutr-stat-goals').textContent = goalSnap.size;

    // Update sidebar badge
    const badge = document.getElementById('nav-nutrition-count');
    if (badge && pendSnap.size > 0) {
      badge.textContent = pendSnap.size;
      badge.style.display = 'inline-block';
    }
  } catch (e) {
    console.error('[Nutrition] loadNutritionStats error:', e);
  }
}

// ── Sub-tab switcher ────────────────────────────────────────────────────────

function switchNutrTab(tab, btn) {
  document.querySelectorAll('.nutr-subtab').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.nutr-subtab-content').forEach(c => c.style.display = 'none');
  btn.classList.add('active');
  const el = document.getElementById('nutr-tab-' + tab);
  if (el) el.style.display = 'block';
}

// ── Nutritionists ────────────────────────────────────────────────────────────

async function loadNutritionistsList() {
  const container = document.getElementById('nutr-nutritionists-list');
  if (!container) return;
  container.innerHTML = '<div class=”loading”>Loading nutritionists…</div>';
  try {
    const snap = await db.collection('nutritionists').orderBy('createdAt', 'desc').get();
    _nutrNutritionists = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderNutritionistsList();
  } catch (e) {
    // Fallback: load without ordering if index not ready
    try {
      const snap = await db.collection('nutritionists').get();
      _nutrNutritionists = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      renderNutritionistsList();
    } catch (e2) {
      container.innerHTML = '<div class=”empty-state”>Error loading nutritionists: ' + escHtml(e2.message) + '</div>';
    }
  }
}

function renderNutritionistsList() {
  const container = document.getElementById('nutr-nutritionists-list');
  if (!container) return;
  const query    = (document.getElementById('nutr-search')?.value || '').toLowerCase();
  const avFilter = document.getElementById('nutr-filter-available')?.value;

  let list = _nutrNutritionists.filter(n => {
    const matchSearch = !query ||
      (n.name || '').toLowerCase().includes(query) ||
      (n.specialization || '').toLowerCase().includes(query) ||
      (n.city || '').toLowerCase().includes(query) ||
      (n.qualification || '').toLowerCase().includes(query);
    const matchAvail = avFilter === '' || String(n.isAvailable) === avFilter;
    return matchSearch && matchAvail;
  });

  if (list.length === 0) {
    container.innerHTML = '<div class=”empty-state” style=”padding:40px;text-align:center;color:var(--text-muted);”>No nutritionists found. <a href=”#” onclick=”openAddNutritionistModal();return false;” style=”color:#2e7d32;”>Add the first one</a></div>';
    return;
  }

  let html = '';
  list.forEach(n => {
    const initials = (n.name || 'N').charAt(0).toUpperCase();
    const avatarHtml = n.photoUrl
      ? `<img src=”${escHtml(n.photoUrl)}” alt=”${escHtml(n.name)}” onerror=”this.style.display='none'” />`
      : initials;
    const modeIcons = [
      n.isOnlineAvailable   ? '<span title=”Online” style=”font-size:11px;background:#e8f5e9;color:#2e7d32;padding:2px 7px;border-radius:4px;”>Online</span>' : '',
      n.isInPersonAvailable ? '<span title=”In-Person” style=”font-size:11px;background:#e3f2fd;color:#1565c0;padding:2px 7px;border-radius:4px;”>In-Person</span>' : '',
    ].filter(Boolean).join(' ');

    html += `
      <div class=”nutr-table-row”>
        <div class=”nutr-avatar”>${avatarHtml}</div>
        <div class=”nutr-info”>
          <div class=”name”>${escHtml(n.name || '—')}</div>
          <div class=”spec”>${escHtml(n.specialization || '—')}</div>
          <div class=”meta”>${escHtml(n.qualification || '')}${n.city ? ' · ' + escHtml(n.city) : ''}${n.experienceYears ? ' · ' + escHtml(String(n.experienceYears)) + ' yrs exp' : ''}</div>
        </div>
        <div style=”flex-shrink:0;”>${modeIcons}</div>
        <div class=”nutr-rating”><i class=”ti ti-star-filled” style=”font-size:12px;”></i> ${escHtml(String(n.rating || 0))} <span style=”color:var(--text-muted);”>(${escHtml(String(n.reviewCount || 0))})</span></div>
        <div class=”nutr-fee”>₹${escHtml(String(n.consultationFee || 0))}</div>
        <div style=”flex-shrink:0;”>
          <span class=”${n.isAvailable ? 'nutr-badge-available' : 'nutr-badge-unavailable'}”>${n.isAvailable ? 'Available' : 'Unavailable'}</span>
        </div>
        <div style=”display:flex;gap:6px;flex-shrink:0;”>
          <button class=”btn-icon” title=”Edit” onclick=”openEditNutritionistModal('${escHtml(n.id)}')”><i class=”ti ti-pencil”></i></button>
          <button class=”btn-icon btn-icon-danger” title=”Delete” onclick=”deleteNutritionist('${escHtml(n.id)}','${escHtml(n.name || '')}')”><i class=”ti ti-trash”></i></button>
        </div>
      </div>`;
  });
  container.innerHTML = html;
}

// ── Add / Edit Nutritionist Modal ─────────────────────────────────────────────

function openAddNutritionistModal() {
  document.getElementById('nutr-modal-title').textContent = 'Add Nutritionist';
  document.getElementById('nutr-edit-id').value = '';
  ['nutr-f-name','nutr-f-qual','nutr-f-city','nutr-f-clinic','nutr-f-photo','nutr-f-bio','nutr-f-langs','nutr-f-expertise'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  document.getElementById('nutr-f-spec').value = '';
  document.getElementById('nutr-f-exp').value = '';
  document.getElementById('nutr-f-fee').value = '';
  document.getElementById('nutr-f-rating').value = '4.5';
  document.getElementById('nutr-f-reviews').value = '0';
  document.getElementById('nutr-f-available').checked = true;
  document.getElementById('nutr-f-online').checked = true;
  document.getElementById('nutr-f-inperson').checked = false;
  document.getElementById('nutr-modal-overlay').style.display = 'block';
  document.getElementById('nutr-modal').style.display = 'block';
}

function openEditNutritionistModal(id) {
  const n = _nutrNutritionists.find(x => x.id === id);
  if (!n) return;
  document.getElementById('nutr-modal-title').textContent = 'Edit Nutritionist';
  document.getElementById('nutr-edit-id').value = id;
  document.getElementById('nutr-f-name').value = n.name || '';
  document.getElementById('nutr-f-qual').value = n.qualification || '';
  document.getElementById('nutr-f-spec').value = n.specialization || '';
  document.getElementById('nutr-f-exp').value = n.experienceYears || '';
  document.getElementById('nutr-f-fee').value = n.consultationFee || '';
  document.getElementById('nutr-f-city').value = n.city || '';
  document.getElementById('nutr-f-clinic').value = n.clinicName || '';
  document.getElementById('nutr-f-photo').value = n.photoUrl || '';
  document.getElementById('nutr-f-bio').value = n.bio || '';
  document.getElementById('nutr-f-langs').value = (n.languages || []).join(', ');
  document.getElementById('nutr-f-expertise').value = (n.expertiseAreas || []).join(', ');
  document.getElementById('nutr-f-rating').value = n.rating || 4.5;
  document.getElementById('nutr-f-reviews').value = n.reviewCount || 0;
  document.getElementById('nutr-f-available').checked = n.isAvailable !== false;
  document.getElementById('nutr-f-online').checked = n.isOnlineAvailable !== false;
  document.getElementById('nutr-f-inperson').checked = !!n.isInPersonAvailable;
  document.getElementById('nutr-modal-overlay').style.display = 'block';
  document.getElementById('nutr-modal').style.display = 'block';
}

function closeNutritionistModal() {
  document.getElementById('nutr-modal-overlay').style.display = 'none';
  document.getElementById('nutr-modal').style.display = 'none';
}

async function saveNutritionist() {
  const btn = document.getElementById('nutr-modal-save-btn');
  const name   = document.getElementById('nutr-f-name').value.trim();
  const qual   = document.getElementById('nutr-f-qual').value.trim();
  const spec   = document.getElementById('nutr-f-spec').value;
  const fee    = parseFloat(document.getElementById('nutr-f-fee').value) || 0;

  if (!name || !qual || !spec || fee <= 0) {
    showToast('Please fill in Name, Qualification, Specialization and Consultation Fee.');
    return;
  }

  const toSplit = str => str.split(',').map(s => s.trim()).filter(Boolean);
  const data = {
    name,
    qualification: qual,
    specialization: spec,
    experienceYears: parseInt(document.getElementById('nutr-f-exp').value) || 0,
    consultationFee: fee,
    city: document.getElementById('nutr-f-city').value.trim(),
    clinicName: document.getElementById('nutr-f-clinic').value.trim(),
    photoUrl: document.getElementById('nutr-f-photo').value.trim(),
    bio: document.getElementById('nutr-f-bio').value.trim(),
    languages: toSplit(document.getElementById('nutr-f-langs').value),
    expertiseAreas: toSplit(document.getElementById('nutr-f-expertise').value),
    rating: parseFloat(document.getElementById('nutr-f-rating').value) || 4.5,
    reviewCount: parseInt(document.getElementById('nutr-f-reviews').value) || 0,
    isAvailable: document.getElementById('nutr-f-available').checked,
    isOnlineAvailable: document.getElementById('nutr-f-online').checked,
    isInPersonAvailable: document.getElementById('nutr-f-inperson').checked,
    availableDays: ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'],
    slots: {},
  };

  const editId = document.getElementById('nutr-edit-id').value;
  const orig = btn.innerHTML;
  btn.innerHTML = '<i class=”ti ti-loader-2”></i> Saving…'; btn.disabled = true;

  try {
    if (editId) {
      await db.collection('nutritionists').doc(editId).update({ ...data, updatedAt: firebase.firestore.FieldValue.serverTimestamp() });
      showToast('Nutritionist updated successfully.');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('nutritionists').add(data);
      showToast('Nutritionist added successfully.');
    }
    closeNutritionistModal();
    loadNutritionistsList();
    loadNutritionStats();
  } catch (e) {
    showToast('Error saving nutritionist: ' + e.message);
  } finally {
    btn.innerHTML = orig; btn.disabled = false;
  }
}

async function deleteNutritionist(id, name) {
  if (!confirm('Delete nutritionist “' + name + '”? This cannot be undone.')) return;
  try {
    await db.collection('nutritionists').doc(id).delete();
    showToast('Nutritionist deleted.');
    loadNutritionistsList();
    loadNutritionStats();
  } catch (e) {
    showToast('Error deleting: ' + e.message);
  }
}

// ── Appointments ─────────────────────────────────────────────────────────────

async function loadNutritionAppointments() {
  const container = document.getElementById('nutr-appointments-list');
  if (!container) return;
  container.innerHTML = '<div class=”loading”>Loading appointments…</div>';

  const statusFilter = (document.getElementById('nutr-appt-filter')?.value || '').trim();
  console.log('[Nutrition] loadNutritionAppointments start, filter:', statusFilter || 'none');
  try {
    let ref = db.collection('nutrition_appointments').limit(200);
    if (statusFilter) ref = db.collection('nutrition_appointments').where('status', '==', statusFilter).limit(200);
    const snap = await ref.get();
    console.log('[Nutrition] appointments snap size:', snap.size);

    if (snap.empty) {
      container.innerHTML = '<div class=”empty-state” style=”padding:40px;text-align:center;color:var(--text-muted);”>No appointments found.</div>';
      return;
    }

    // Sort newest-first client-side
    const docs = snap.docs.slice().sort((a, b) => {
      const ta = a.data().createdAt?.seconds || 0;
      const tb = b.data().createdAt?.seconds || 0;
      return tb - ta;
    });

    let html = `
      <div class=”appt-row-header”>
        <span>Patient</span><span>Nutritionist</span><span>Date</span><span>Time</span><span>Type</span><span>Status</span><span>Actions</span>
      </div>`;
    docs.forEach(doc => {
      const a = doc.data();
      const id = doc.id;
      const statusClass = {pending:'pill-pending',confirmed:'pill-confirmed',completed:'pill-completed',cancelled:'pill-cancelled'}[a.status] || 'pill-pending';

      let actionBtns = '';
      if (a.status === 'pending') {
        actionBtns = `
          <button class=”btn-icon” title=”Confirm” style=”background:#e8f5e9;color:#2e7d32;border:none;” onclick=”updateNutrApptStatus('${escHtml(id)}','confirmed')”><i class=”ti ti-check”></i></button>
          <button class=”btn-icon btn-icon-danger” title=”Cancel” onclick=”updateNutrApptStatus('${escHtml(id)}','cancelled')”><i class=”ti ti-x”></i></button>`;
      } else if (a.status === 'confirmed') {
        actionBtns = `
          <button class=”btn-icon” title=”Mark Completed” style=”background:#e3f2fd;color:#1565c0;border:none;” onclick=”updateNutrApptStatus('${escHtml(id)}','completed')”><i class=”ti ti-circle-check”></i></button>
          <button class=”btn-icon btn-icon-danger” title=”Cancel” onclick=”updateNutrApptStatus('${escHtml(id)}','cancelled')”><i class=”ti ti-x”></i></button>`;
      } else {
        actionBtns = `
          <button class=”btn-icon btn-icon-danger” title=”Delete” onclick=”deleteNutrAppt('${escHtml(id)}')”><i class=”ti ti-trash”></i></button>`;
      }

      html += `
        <div class=”appt-row”>
          <span style=”font-weight:600;”>${escHtml(a.userName || 'Patient')}</span>
          <span>${escHtml(a.nutritionistName || '—')}</span>
          <span>${escHtml(a.date || '—')}</span>
          <span>${escHtml(a.timeSlot || '—')}</span>
          <span style=”font-size:11px;”>${escHtml(a.consultationType || '—')}</span>
          <span><span class=”pill ${statusClass}”>${escHtml(a.status || '—')}</span></span>
          <span style=”display:flex;gap:5px;”>${actionBtns}</span>
        </div>`;
    });
    container.innerHTML = html;
  } catch (e) {
    console.error('[Nutrition] loadNutritionAppointments error:', e);
    container.innerHTML = `<div class=”empty-state” style=”padding:24px;text-align:center;”>
      <p style=”color:var(--danger);font-weight:600;”>Failed to load appointments</p>
      <p style=”color:var(--text-muted);font-size:12px;”>${escHtml(e.message)}</p>
      <p style=”color:var(--text-muted);font-size:11px;”>Make sure Firestore rules are deployed: <code>firebase deploy --only firestore:rules</code></p>
    </div>`;
  }
}

async function updateNutrApptStatus(id, status) {
  const labels = { confirmed: 'Confirm', completed: 'Complete', cancelled: 'Cancel' };
  if (!confirm(`${labels[status] || 'Update'} this appointment?`)) return;
  try {
    await db.collection('nutrition_appointments').doc(id).update({
      status,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast('Appointment ' + status + '.');
    loadNutritionAppointments();
    loadNutritionStats();
  } catch (e) {
    showToast('Error: ' + e.message);
  }
}

async function deleteNutrAppt(id) {
  if (!confirm('Permanently delete this appointment record?')) return;
  try {
    await db.collection('nutrition_appointments').doc(id).delete();
    showToast('Appointment deleted.');
    loadNutritionAppointments();
    loadNutritionStats();
  } catch (e) {
    showToast('Error: ' + e.message);
  }
}

// ── Meal Logs ────────────────────────────────────────────────────────────────

async function loadMealLogs() {
  const container = document.getElementById('nutr-meal-logs-list');
  if (!container) return;
  container.innerHTML = '<div class=”loading”>Loading meal logs…</div>';

  const dp = document.getElementById('nutr-meal-date');
  const dateKey = dp?.value || new Date().toISOString().slice(0, 10);
  console.log('[Nutrition] loadMealLogs start, dateKey:', dateKey);

  try {
    const snap = await db.collection('meal_tracking')
      .where('dateKey', '==', dateKey)
      .limit(300)
      .get();
    console.log('[Nutrition] meal logs snap size:', snap.size);

    if (snap.empty) {
      container.innerHTML = '<div class=”empty-state” style=”padding:40px;text-align:center;color:var(--text-muted);”>No meal logs for ' + escHtml(dateKey) + '.</div>';
      return;
    }

    // Sort by loggedAt ascending client-side
    const docs = snap.docs.slice().sort((a, b) => {
      const ta = a.data().loggedAt?.seconds || 0;
      const tb = b.data().loggedAt?.seconds || 0;
      return tb - ta;
    });

    let html = `
      <div class=”meal-row-header”>
        <span>Food Item</span><span>Meal Type</span><span>Calories</span><span>Protein</span><span>Carbs</span><span>Fat</span><span></span>
      </div>`;
    docs.forEach(doc => {
      const m = doc.data();
      const id = doc.id;
      const typeClass = {breakfast:'meal-type-breakfast',lunch:'meal-type-lunch',dinner:'meal-type-dinner',snack:'meal-type-snack'}[m.mealType] || 'meal-type-snack';
      const userLabel = m.userName
        ? escHtml(m.userName)
        : (m.userId ? '<span style=”font-family:monospace;font-size:10px;color:var(--text-muted);”>' + escHtml(m.userId.slice(0, 8)) + '…</span>' : '');
      html += `
        <div class=”meal-row”>
          <span>
            <div style=”font-weight:600;”>${escHtml(m.foodName || '—')}</div>
            <div style=”font-size:11px;color:var(--text-muted);margin-top:1px;”>${userLabel}</div>
          </span>
          <span><span class=”pill ${typeClass}” style=”font-size:10px;”>${escHtml(m.mealType || '—')}</span></span>
          <span style=”font-weight:700;color:#e65100;”>${escHtml(String(Math.round(m.calories || 0)))} kcal</span>
          <span style=”color:#1565c0;”>${escHtml(String(Math.round(m.protein || 0)))}g</span>
          <span style=”color:#2e7d32;”>${escHtml(String(Math.round(m.carbs || 0)))}g</span>
          <span style=”color:#7b1fa2;”>${escHtml(String(Math.round(m.fat || 0)))}g</span>
          <span>
            <button class=”btn-icon btn-icon-danger” title=”Delete” onclick=”deleteAdminMealLog('${escHtml(id)}')”><i class=”ti ti-trash”></i></button>
          </span>
        </div>`;
    });
    container.innerHTML = html;
  } catch (e) {
    console.error('[Nutrition] loadMealLogs error:', e);
    container.innerHTML = `<div class=”empty-state” style=”padding:24px;text-align:center;”>
      <p style=”color:var(--danger);font-weight:600;”>Failed to load meal logs</p>
      <p style=”color:var(--text-muted);font-size:12px;”>${escHtml(e.message)}</p>
      <p style=”color:var(--text-muted);font-size:11px;”>Deploy updated rules: <code>firebase deploy --only firestore:rules</code></p>
    </div>`;
  }
}

async function deleteAdminMealLog(id) {
  if (!confirm('Delete this meal log entry?')) return;
  try {
    await db.collection('meal_tracking').doc(id).delete();
    showToast('Meal log deleted.');
    loadMealLogs();
  } catch (e) {
    showToast('Error: ' + e.message);
  }
}

// ── Goals ────────────────────────────────────────────────────────────────────

const _goalLabels = {
  weight_loss:'Weight Loss', weight_gain:'Weight Gain', diabetes:'Diabetes Diet',
  pregnancy:'Pregnancy Nutrition', fitness:'Fitness', pcos:'PCOS', heart_health:'Heart Healthy',
};

let _nutrGoalsShowAll = false;

function toggleNutrGoalsFilter() {
  _nutrGoalsShowAll = !_nutrGoalsShowAll;
  loadNutritionGoals();
}

async function loadNutritionGoals() {
  const container = document.getElementById('nutr-goals-list');
  if (!container) return;
  container.innerHTML = '<div class=”loading”>Loading goals…</div>';

  try {
    let ref = db.collection('nutrition_goals').limit(150);
    if (!_nutrGoalsShowAll) ref = db.collection('nutrition_goals').where('isActive', '==', true).limit(150);
    const snap = await ref.get();

    const toggleLabel = _nutrGoalsShowAll ? 'Show Active Only' : 'Show All Goals';
    const headerExtra = `<div style=”padding:10px 16px;border-bottom:1px solid var(--border);display:flex;justify-content:flex-end;”>
      <button class=”btn-secondary” style=”font-size:12px;padding:5px 12px;” onclick=”toggleNutrGoalsFilter()”>${escHtml(toggleLabel)}</button>
    </div>`;

    if (snap.empty) {
      container.innerHTML = headerExtra + '<div class=”empty-state” style=”padding:40px;text-align:center;color:var(--text-muted);”>No nutrition goals found.</div>';
      return;
    }

    let html = headerExtra + `
      <div class=”goal-row-header”>
        <span>Patient</span><span>Goal Type</span><span>Target Cal</span><span>Target Wt</span><span>Current Wt</span><span>Status</span><span>Actions</span>
      </div>`;
    snap.forEach(doc => {
      const g = doc.data();
      const id = doc.id;
      const isActive = g.isActive !== false;
      const statusBadge = isActive
        ? '<span class=”pill pill-active”>Active</span>'
        : '<span class=”pill pill-cancelled” style=”background:#f5f5f5;color:#9e9e9e;”>Inactive</span>';
      const userLabel = g.userName
        ? escHtml(g.userName)
        : '<span style=”font-family:monospace;font-size:10px;”>' + escHtml((g.userId || '').slice(0, 10)) + '…</span>';

      html += `
        <div class=”goal-row”>
          <span>${userLabel}</span>
          <span style=”font-weight:600;color:#2e7d32;”>${escHtml(_goalLabels[g.goalType] || g.goalType || '—')}</span>
          <span style=”font-weight:700;color:#e65100;”>${escHtml(String(Math.round(g.targetCalories || 0)))} kcal</span>
          <span>${g.targetWeight ? escHtml(String(g.targetWeight)) + ' kg' : '—'}</span>
          <span>${g.currentWeight ? escHtml(String(g.currentWeight)) + ' kg' : '—'}</span>
          <span>${statusBadge}</span>
          <span style=”display:flex;gap:5px;”>
            ${isActive ? `<button class=”btn-icon” title=”Deactivate” style=”background:#fff8e1;color:#f57f17;border:none;” onclick=”deactivateNutrGoal('${escHtml(id)}')”><i class=”ti ti-player-pause”></i></button>` : ''}
            <button class=”btn-icon btn-icon-danger” title=”Delete” onclick=”deleteNutrGoal('${escHtml(id)}')”><i class=”ti ti-trash”></i></button>
          </span>
        </div>`;
    });
    container.innerHTML = html;
  } catch (e) {
    container.innerHTML = '<div class=”empty-state” style=”padding:24px;color:var(--text-muted);”>Error: ' + escHtml(e.message) + '</div>';
    console.error('[Nutrition] loadNutritionGoals error:', e);
  }
}

async function deactivateNutrGoal(id) {
  if (!confirm('Deactivate this nutrition goal?')) return;
  try {
    await db.collection('nutrition_goals').doc(id).update({
      isActive: false,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
    showToast('Goal deactivated.');
    loadNutritionGoals();
    loadNutritionStats();
  } catch (e) {
    showToast('Error: ' + e.message);
  }
}

async function deleteNutrGoal(id) {
  if (!confirm('Permanently delete this nutrition goal?')) return;
  try {
    await db.collection('nutrition_goals').doc(id).delete();
    showToast('Goal deleted.');
    loadNutritionGoals();
    loadNutritionStats();
  } catch (e) {
    showToast('Error: ' + e.message);
  }
}

// ============================================
//   DIET PLANS (admin-managed, shown in Flutter app)
// ============================================

let _nutrDietPlans = [];   // client-side cache

const _dpIconEmoji = {
  monitor_weight: '⚖️', bloodtype: '', favorite: '❤️',
  pregnant_woman: '', fitness_center: '️', spa: '',
  restaurant: '️', eco: '', local_hospital: '',
};
const _dpColorHex = {
  green: '#2E7D32', red: '#B71C1C', pink: '#C2185B',
  purple: '#7B1FA2', blue: '#1565C0', teal: '#00897B',
  orange: '#E65100', brown: '#4E342E',
};

async function loadDietPlans() {
  const container = document.getElementById('nutr-diet-plans-list');
  if (!container) return;
  container.innerHTML = '<div class="loading">Loading diet plans…</div>';
  try {
    const snap = await db.collection('diet_plans').orderBy('order').get();
    _nutrDietPlans = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderDietPlans();
  } catch (_) {
    // Fallback without orderBy
    try {
      const snap = await db.collection('diet_plans').get();
      _nutrDietPlans = snap.docs.map(d => ({ id: d.id, ...d.data() })).sort((a, b) => (a.order || 99) - (b.order || 99));
      renderDietPlans();
    } catch (e2) {
      container.innerHTML = '<div class="empty-state" style="padding:40px;text-align:center;color:var(--text-muted);">Error: ' + escHtml(e2.message) + '</div>';
    }
  }
}

function renderDietPlans() {
  const container = document.getElementById('nutr-diet-plans-list');
  if (!container) return;

  if (_nutrDietPlans.length === 0) {
    container.innerHTML = '<div class="empty-state" style="padding:40px;text-align:center;color:var(--text-muted);">No diet plans yet. <a href="#" onclick="openAddDietPlanModal();return false;" style="color:#2e7d32;">Add the first one</a></div>';
    return;
  }

  let html = '';
  _nutrDietPlans.forEach(p => {
    const emoji  = _dpIconEmoji[p.iconKey] || '️';
    const color  = _dpColorHex[p.colorKey] || '#2E7D32';
    const active = p.isActive !== false;
    html += `
      <div class="dp-row">
        <div class="dp-icon" style="background:${escHtml(color)}1a;">${emoji}</div>
        <div class="dp-info">
          <div class="dp-title">${escHtml(p.title || '—')}</div>
          <div class="dp-desc">${escHtml(p.description || '')}</div>
        </div>
        <div class="dp-price">${escHtml(p.price || '')}</div>
        <div style="flex-shrink:0;margin-right:8px;">
          <span class="${active ? 'nutr-badge-available' : 'nutr-badge-unavailable'}">${active ? 'Active' : 'Hidden'}</span>
        </div>
        <div style="display:flex;gap:6px;flex-shrink:0;">
          <button class="btn-icon" title="Edit" onclick="openEditDietPlanModal('${escHtml(p.id)}')"><i class="ti ti-pencil"></i></button>
          <button class="btn-icon btn-icon-danger" title="Delete" onclick="deleteDietPlan('${escHtml(p.id)}','${escHtml(p.title || '')}')"><i class="ti ti-trash"></i></button>
        </div>
      </div>`;
  });
  container.innerHTML = html;
}

function openAddDietPlanModal() {
  document.getElementById('nutr-dp-modal-title').textContent = 'Add Diet Plan';
  document.getElementById('nutr-dp-edit-id').value = '';
  document.getElementById('nutr-dp-title').value = '';
  document.getElementById('nutr-dp-desc').value = '';
  document.getElementById('nutr-dp-price').value = '';
  document.getElementById('nutr-dp-order').value = (_nutrDietPlans.length + 1);
  document.getElementById('nutr-dp-icon').value = 'restaurant';
  document.getElementById('nutr-dp-color').value = 'green';
  document.getElementById('nutr-dp-active').checked = true;
  document.getElementById('nutr-dp-modal-overlay').style.display = 'block';
  document.getElementById('nutr-dp-modal').style.display = 'block';
}

function openEditDietPlanModal(id) {
  const p = _nutrDietPlans.find(x => x.id === id);
  if (!p) return;
  document.getElementById('nutr-dp-modal-title').textContent = 'Edit Diet Plan';
  document.getElementById('nutr-dp-edit-id').value = id;
  document.getElementById('nutr-dp-title').value = p.title || '';
  document.getElementById('nutr-dp-desc').value = p.description || '';
  document.getElementById('nutr-dp-price').value = p.price || '';
  document.getElementById('nutr-dp-order').value = p.order || '';
  document.getElementById('nutr-dp-icon').value = p.iconKey || 'restaurant';
  document.getElementById('nutr-dp-color').value = p.colorKey || 'green';
  document.getElementById('nutr-dp-active').checked = p.isActive !== false;
  document.getElementById('nutr-dp-modal-overlay').style.display = 'block';
  document.getElementById('nutr-dp-modal').style.display = 'block';
}

function closeDietPlanModal() {
  document.getElementById('nutr-dp-modal-overlay').style.display = 'none';
  document.getElementById('nutr-dp-modal').style.display = 'none';
}

async function saveDietPlan() {
  const btn   = document.getElementById('nutr-dp-save-btn');
  const title = document.getElementById('nutr-dp-title').value.trim();
  const desc  = document.getElementById('nutr-dp-desc').value.trim();
  if (!title || !desc) {
    showToast('Title and Description are required.');
    return;
  }
  const data = {
    title,
    description: desc,
    price: document.getElementById('nutr-dp-price').value.trim(),
    order: parseInt(document.getElementById('nutr-dp-order').value) || 99,
    iconKey: document.getElementById('nutr-dp-icon').value,
    colorKey: document.getElementById('nutr-dp-color').value,
    isActive: document.getElementById('nutr-dp-active').checked,
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  };

  const editId = document.getElementById('nutr-dp-edit-id').value;
  const orig = btn.innerHTML;
  btn.innerHTML = '<i class="ti ti-loader-2"></i> Saving…'; btn.disabled = true;

  try {
    if (editId) {
      await db.collection('diet_plans').doc(editId).update(data);
      showToast('Diet plan updated.');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('diet_plans').add(data);
      showToast('Diet plan added. It will appear in the MedNU app.');
    }
    closeDietPlanModal();
    loadDietPlans();
  } catch (e) {
    showToast('Error: ' + e.message);
  } finally {
    btn.innerHTML = orig; btn.disabled = false;
  }
}

async function deleteDietPlan(id, title) {
  if (!confirm('Delete diet plan "' + title + '"?')) return;
  try {
    await db.collection('diet_plans').doc(id).delete();
    showToast('Diet plan deleted.');
    loadDietPlans();
  } catch (e) {
    showToast('Error: ' + e.message);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OPERATION LOGS PANEL
// ══════════════════════════════════════════════════════════════════════════════

let _logsUnsubscribe = null;
let _allLogs = [];

function initOperationLogs() {
  // Subscribe to real-time updates
  _subscribeToLogs();
}

function _subscribeToLogs() {
  if (_logsUnsubscribe) _logsUnsubscribe();
  const tableEl = document.getElementById('operation-logs-table');
  if (!tableEl) return;

  _logsUnsubscribe = db.collection('operation_logs')
    .orderBy('timestamp', 'desc')
    .limit(200)
    .onSnapshot(snapshot => {
      _allLogs = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
      _updateLogStats(_allLogs);
      filterLogs();
    }, err => {
      console.error('[AdminLogs] Firestore stream error:', err);
    });
}

function _updateLogStats(logs) {
  const today = new Date().toDateString();
  const todayLogs = logs.filter(l => {
    if (!l.timestamp) return false;
    const ts = l.timestamp.toDate ? l.timestamp.toDate() : new Date(l.timestamp);
    return ts.toDateString() === today;
  });
  document.getElementById('log-stat-success').textContent =
    todayLogs.filter(l => l.status === 'success').length;
  document.getElementById('log-stat-error').textContent =
    todayLogs.filter(l => l.status === 'error').length;
  document.getElementById('log-stat-pending').textContent =
    todayLogs.filter(l => l.status === 'pending').length;
  document.getElementById('log-stat-total').textContent = todayLogs.length;

  // Update nav badge for errors
  const errorCount = todayLogs.filter(l => l.status === 'error').length;
  const badge = document.getElementById('nav-error-logs-count');
  if (badge) {
    badge.style.display = errorCount > 0 ? 'inline-flex' : 'none';
    badge.textContent = errorCount;
  }
}

function filterLogs() {
  const typeFilter   = document.getElementById('log-filter-type')?.value   || '';
  const statusFilter = document.getElementById('log-filter-status')?.value || '';
  const actionFilter = document.getElementById('log-filter-action')?.value || '';

  const filtered = _allLogs.filter(log => {
    if (typeFilter   && log.userType !== typeFilter)   return false;
    if (statusFilter && log.status   !== statusFilter) return false;
    if (actionFilter && log.action   !== actionFilter) return false;
    return true;
  });

  _renderLogsTable(filtered);
}

function loadOperationLogs() {
  if (_allLogs.length > 0) {
    filterLogs();
    return;
  }
  _subscribeToLogs();
}

function _renderLogsTable(logs) {
  const el = document.getElementById('operation-logs-table');
  if (!el) return;

  if (logs.length === 0) {
    el.innerHTML = `<div style="padding:40px;text-align:center;color:#9E9E9E;">
      <i class="ti ti-activity" style="font-size:40px;display:block;margin-bottom:10px;"></i>
      No logs match the selected filters
    </div>`;
    return;
  }

  const rows = logs.map(log => {
    const ts = log.timestamp?.toDate ? log.timestamp.toDate() : null;
    const timeStr = ts ? ts.toLocaleString('en-IN', {
      day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
    }) : '—';

    const statusColor = log.status === 'success'
      ? '#1B5E20' : log.status === 'error'
      ? '#C62828' : '#E65100';
    const statusBg = log.status === 'success'
      ? '#E8F5E9' : log.status === 'error'
      ? '#FFEBEE' : '#FFF3E0';

    const userTypeBadge = log.userType === 'doctor'
      ? `<span style="background:#E3F2FD;color:#1565C0;font-size:10px;font-weight:700;padding:2px 7px;border-radius:10px;">DOCTOR</span>`
      : log.userType === 'admin'
        ? `<span style="background:#F3E5F5;color:#6A1B9A;font-size:10px;font-weight:700;padding:2px 7px;border-radius:10px;">ADMIN</span>`
        : `<span style="background:#FCE4EC;color:#880E4F;font-size:10px;font-weight:700;padding:2px 7px;border-radius:10px;">PATIENT</span>`;

    const errorRow = log.status === 'error' && log.errorDetails
      ? `<tr style="background:#FFF8F8;">
           <td colspan="6" style="padding:6px 16px 10px 56px;font-size:11px;color:#C62828;font-family:monospace;">
             ⚠ ${escHtml(log.errorDetails)}
           </td>
         </tr>`
      : '';

    return `<tr>
      <td style="padding:12px 16px;font-size:12px;color:#616161;white-space:nowrap;">${timeStr}</td>
      <td style="padding:12px 8px;">${userTypeBadge}</td>
      <td style="padding:12px 8px;">
        <span style="font-size:12px;font-weight:600;color:#1A1A2E;font-family:monospace;">${escHtml(log.action || '—')}</span>
      </td>
      <td style="padding:12px 8px;font-size:12px;color:#424242;max-width:240px;word-break:break-word;">
        ${escHtml(log.message || '—')}
      </td>
      <td style="padding:12px 8px;">
        <span style="background:${statusBg};color:${statusColor};font-size:10px;font-weight:700;padding:3px 9px;border-radius:12px;text-transform:uppercase;">
          ${escHtml(log.status || '?')}
        </span>
      </td>
      <td style="padding:12px 8px;font-size:11px;color:#9E9E9E;">${escHtml(log.userId?.substring(0,8) || '—')}…</td>
    </tr>${errorRow}`;
  }).join('');

  el.innerHTML = `<table style="width:100%;border-collapse:collapse;">
    <thead>
      <tr style="background:#F5F5F5;border-bottom:2px solid #E0E0E0;">
        <th style="padding:10px 16px;text-align:left;font-size:11px;font-weight:700;color:#757575;">TIME</th>
        <th style="padding:10px 8px;text-align:left;font-size:11px;font-weight:700;color:#757575;">USER TYPE</th>
        <th style="padding:10px 8px;text-align:left;font-size:11px;font-weight:700;color:#757575;">ACTION</th>
        <th style="padding:10px 8px;text-align:left;font-size:11px;font-weight:700;color:#757575;">MESSAGE</th>
        <th style="padding:10px 8px;text-align:left;font-size:11px;font-weight:700;color:#757575;">STATUS</th>
        <th style="padding:10px 8px;text-align:left;font-size:11px;font-weight:700;color:#757575;">USER ID</th>
      </tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>`;
}

// Pulse the LIVE dot
setInterval(() => {
  const dot = document.getElementById('log-live-dot');
  if (dot) {
    dot.style.opacity = dot.style.opacity === '0.3' ? '1' : '0.3';
  }
}, 800);

// ── GLOBAL SEARCH ─────────────────────────────────────────────────────────────

let _gsOpen = false;
let _gsFilter = 'all';
let _gsDebounce = null;
let _gsFocusIdx = -1;
let _gsResults = [];

const GS_COLLECTIONS = {
  doctors:      { col: 'doctors',        icon: 'ti-stethoscope', bg: '#F5E6F0', fg: '#522546', label: 'Doctors',      fields: ['name','specialty','specialisation','email','phone'], tab: 'doctors',      badge: d => d.status || 'active' },
  patients:     { col: 'users',          icon: 'ti-users',       bg: '#E8F5E9', fg: '#2E7D32', label: 'Patients',     fields: ['name','email','phone'],               tab: 'patients',     badge: () => 'patient' },
  hospitals:    { col: 'hospitals',      icon: 'ti-building-hospital', bg: '#E3F2FD', fg: '#1565C0', label: 'Hospitals',    fields: ['name','type','address','city'],    tab: 'hospitals',    badge: d => d.type || 'hospital' },
  ambulances:   { col: 'ambulances',     icon: 'ti-ambulance',   bg: '#FFF3E0', fg: '#E65100', label: 'Ambulances',   fields: ['name','provider','phone','area'],      tab: 'ambulances',   badge: d => d.status || 'active' },
  tickets:      { col: 'support_tickets',icon: 'ti-ticket',      bg: '#FCE4EC', fg: '#B71C1C', label: 'Tickets',      fields: ['title','user','description'],          tab: 'tickets',      badge: d => d.priority || 'medium' },
  appointments: { col: 'appointments',   icon: 'ti-calendar',    bg: '#E8EAF6', fg: '#283593', label: 'Appointments', fields: ['patient','doctor','service'],           tab: 'appointments', badge: d => d.status || 'pending' },
  referrals:    { col: 'referrals',      icon: 'ti-share',       bg: '#F3E5F5', fg: '#6A1B9A', label: 'Referrals',    fields: ['referrerName','referredName','code'],   tab: 'referrals',    badge: () => 'referral' },
  banners:      { col: 'banners',        icon: 'ti-photo',       bg: '#E0F7FA', fg: '#006064', label: 'Banners',      fields: ['title','subtitle'],                    tab: 'banners',      badge: d => d.enabled ? 'active' : 'inactive' },
  service_requests: { col: 'service_requests', icon: 'ti-alert-triangle', bg: '#FFF8E1', fg: '#F57F17', label: 'Service Requests', fields: ['type','userName','description'], tab: 'ambulances', badge: d => d.status || 'pending' },
  medicines:    { col: 'medicines',      icon: 'ti-pill',        bg: '#E8F5E9', fg: '#1B5E20', label: 'Medicines',    fields: ['name','generic','category'],           tab: 'medicines',    badge: d => d.category || 'medicine' },
  maternity:    { col: 'maternity_profiles', icon: 'ti-heart', bg: '#FCE4EC', fg: '#880E4F', label: 'Maternity', fields: ['name','phone'],                          tab: 'maternity',    badge: () => 'maternity' },
};

function openGlobalSearch() {
  _gsOpen = true;
  _gsFilter = 'all';
  _gsFocusIdx = -1;
  _gsResults = [];
  document.getElementById('global-search-overlay').style.display = '';
  document.getElementById('global-search-modal').style.display = '';
  document.getElementById('gs-input').value = '';
  document.getElementById('gs-clear-btn').style.display = 'none';
  showGsHome();
  setTimeout(() => document.getElementById('gs-input').focus(), 50);
  document.body.style.overflow = 'hidden';
  loadRecentSearches();
}

function closeGlobalSearch() {
  _gsOpen = false;
  document.getElementById('global-search-overlay').style.display = 'none';
  document.getElementById('global-search-modal').style.display = 'none';
  document.body.style.overflow = '';
  if (_gsDebounce) clearTimeout(_gsDebounce);
}

function clearGlobalSearch() {
  document.getElementById('gs-input').value = '';
  document.getElementById('gs-clear-btn').style.display = 'none';
  showGsHome();
  document.getElementById('gs-input').focus();
}

function showGsHome() {
  document.getElementById('gs-home').style.display = '';
  document.getElementById('gs-results').style.display = 'none';
  document.getElementById('gs-loading').style.display = 'none';
  document.getElementById('gs-empty').style.display = 'none';
  document.getElementById('gs-result-count').textContent = '';
  _gsFocusIdx = -1;
  _gsResults = [];
}

function showGsLoading() {
  document.getElementById('gs-home').style.display = 'none';
  document.getElementById('gs-results').style.display = 'none';
  document.getElementById('gs-loading').style.display = '';
  document.getElementById('gs-empty').style.display = 'none';
}

function showGsResults(items) {
  document.getElementById('gs-home').style.display = 'none';
  document.getElementById('gs-loading').style.display = 'none';
  document.getElementById('gs-empty').style.display = 'none';
  _gsResults = items;
  _gsFocusIdx = -1;
  if (!items.length) {
    document.getElementById('gs-results').style.display = 'none';
    document.getElementById('gs-empty').style.display = '';
    document.getElementById('gs-empty-msg').textContent = 'No results for "' + escHtml(document.getElementById('gs-input').value) + '"';
    document.getElementById('gs-result-count').textContent = '';
    return;
  }
  document.getElementById('gs-results').style.display = '';
  document.getElementById('gs-result-count').textContent = items.length + ' result' + (items.length !== 1 ? 's' : '');
  renderGsResults(items, document.getElementById('gs-input').value);
}

function renderGsResults(items, query) {
  const groups = {};
  items.forEach(item => {
    if (!groups[item._type]) groups[item._type] = [];
    groups[item._type].push(item);
  });

  const q = query.trim().toLowerCase();
  let html = '';
  Object.entries(groups).forEach(([type, docs]) => {
    const cfg = GS_COLLECTIONS[type];
    if (!cfg) return;
    html += `<div class="gs-group">
      <div class="gs-group-header"><i class="ti ${cfg.icon}"></i>${cfg.label} <span style="color:var(--text-muted);font-weight:400;">(${docs.length})</span></div>`;
    docs.forEach((doc, i) => {
      const title = highlightMatch(doc._title || doc.name || doc.id, q);
      const sub = escHtml(doc._sub || '');
      const badge = cfg.badge(doc);
      const badgeColor = getBadgeColor(badge);
      const globalIdx = items.indexOf(doc);
      html += `<div class="gs-result-item" data-idx="${globalIdx}" onclick="selectGsResult(${globalIdx})">
        <div class="gs-result-icon" style="background:${cfg.bg};color:${cfg.fg};"><i class="ti ${cfg.icon}"></i></div>
        <div class="gs-result-info">
          <div class="gs-result-title">${title}</div>
          ${sub ? `<div class="gs-result-sub">${sub}</div>` : ''}
        </div>
        <span class="gs-result-badge" style="background:${badgeColor.bg};color:${badgeColor.fg};">${escHtml(badge)}</span>
        <i class="ti ti-chevron-right gs-result-arrow"></i>
      </div>`;
    });
    html += `</div>`;
  });
  document.getElementById('gs-results-inner').innerHTML = html;
}

function highlightMatch(text, query) {
  if (!text || !query) return escHtml(String(text || ''));
  const escaped = escHtml(String(text));
  const q = escHtml(query);
  try {
    const regex = new RegExp('(' + q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'gi');
    return escaped.replace(regex, '<mark>$1</mark>');
  } catch(e) { return escaped; }
}

function getBadgeColor(status) {
  const map = {
    active: { bg: '#E8F5E9', fg: '#1E8E3E' },
    inactive: { bg: '#FAFAFA', fg: '#757575' },
    pending: { bg: '#FFF3E0', fg: '#E65100' },
    approved: { bg: '#E8F5E9', fg: '#1E8E3E' },
    rejected: { bg: '#FCE4EC', fg: '#B71C1C' },
    completed: { bg: '#E8F5E9', fg: '#1E8E3E' },
    open: { bg: '#FFF3E0', fg: '#E65100' },
    closed: { bg: '#FAFAFA', fg: '#757575' },
    high: { bg: '#FCE4EC', fg: '#B71C1C' },
    medium: { bg: '#FFF3E0', fg: '#E65100' },
    low: { bg: '#E8F5E9', fg: '#1E8E3E' },
    patient: { bg: '#E8F5E9', fg: '#1E8E3E' },
    hospital: { bg: '#E3F2FD', fg: '#1565C0' },
    referral: { bg: '#F3E5F5', fg: '#6A1B9A' },
    maternity: { bg: '#FCE4EC', fg: '#880E4F' },
    medicine: { bg: '#E8F5E9', fg: '#1B5E20' },
  };
  return map[String(status).toLowerCase()] || { bg: '#F5F5F5', fg: '#616161' };
}

function selectGsResult(idx) {
  const item = _gsResults[idx];
  if (!item) return;
  saveRecentSearch(document.getElementById('gs-input').value, item._title || item.name || '', item._type);
  closeGlobalSearch();
  const cfg = GS_COLLECTIONS[item._type];
  if (cfg && typeof switchTab === 'function') {
    const tabTitles = { doctors:'Doctors', patients:'Patients', hospitals:'Hospitals', ambulances:'Ambulances', tickets:'Support Tickets', appointments:'Appointments', referrals:'Referrals', banners:'Banners', analytics:'Analytics', wallet:'Wallet', medicines:'Medicines', maternity:'Maternity', requests:'Service Requests' };
    switchTab(cfg.tab, tabTitles[cfg.tab] || cfg.tab);
  }
}

function setSearchFilter(type, btn) {
  _gsFilter = type;
  document.querySelectorAll('.gs-filter-chip').forEach(c => c.classList.remove('active'));
  btn.classList.add('active');
  const q = document.getElementById('gs-input').value.trim();
  if (q.length >= 1) runSearch(q);
}

function navigateFromSearch(tab) {
  closeGlobalSearch();
  const tabTitles = { doctors:'Doctors', patients:'Patients', hospitals:'Hospitals', ambulances:'Ambulances', tickets:'Support Tickets', appointments:'Appointments', referrals:'Referrals', banners:'Banners', analytics:'Analytics', wallet:'Wallet', medicines:'Medicines', maternity:'Maternity', requests:'Service Requests' };
  if (typeof switchTab === 'function') switchTab(tab, tabTitles[tab] || tab);
}

// Keyboard navigation
document.addEventListener('keydown', e => {
  if (e.key === '/' && !_gsOpen && !e.target.matches('input,textarea,select,[contenteditable]')) {
    e.preventDefault();
    openGlobalSearch();
    return;
  }
  if (!_gsOpen) return;
  if (e.key === 'Escape') { closeGlobalSearch(); return; }
  if (e.key === 'ArrowDown') { e.preventDefault(); moveFocus(1); return; }
  if (e.key === 'ArrowUp') { e.preventDefault(); moveFocus(-1); return; }
  if (e.key === 'Enter' && _gsFocusIdx >= 0) { e.preventDefault(); selectGsResult(_gsFocusIdx); return; }
});

function moveFocus(dir) {
  if (!_gsResults.length) return;
  const items = document.querySelectorAll('.gs-result-item');
  if (!items.length) return;
  items.forEach(el => el.classList.remove('focused'));
  _gsFocusIdx = Math.max(0, Math.min(_gsResults.length - 1, _gsFocusIdx + dir));
  const focused = items[_gsFocusIdx];
  if (focused) {
    focused.classList.add('focused');
    focused.scrollIntoView({ block: 'nearest' });
  }
}

// Search input handler
document.addEventListener('DOMContentLoaded', () => {
  const input = document.getElementById('gs-input');
  if (!input) return;
  input.addEventListener('input', () => {
    const q = input.value.trim();
    document.getElementById('gs-clear-btn').style.display = q ? '' : 'none';
    if (_gsDebounce) clearTimeout(_gsDebounce);
    if (!q) { showGsHome(); return; }
    if (q.length < 1) return;
    _gsDebounce = setTimeout(() => runSearch(q), 280);
  });
});

async function runSearch(query) {
  if (!query || query.length < 1) return;
  showGsLoading();
  const q = query.trim().toLowerCase();
  const activeTypes = _gsFilter === 'all' ? Object.keys(GS_COLLECTIONS) : [_gsFilter];
  const allResults = [];

  await Promise.all(activeTypes.map(async type => {
    const cfg = GS_COLLECTIONS[type];
    if (!cfg) return;
    try {
      const snap = await db.collection(cfg.col).limit(200).get();
      snap.forEach(doc => {
        const d = doc.data();
        const searchable = cfg.fields.map(f => String(d[f] || '')).join(' ').toLowerCase();
        if (searchable.includes(q)) {
          const titleField = cfg.fields[0];
          const subFields = cfg.fields.slice(1, 3);
          allResults.push({
            ...d,
            id: doc.id,
            _type: type,
            _title: d[titleField] || doc.id,
            _sub: subFields.map(f => d[f]).filter(Boolean).join(' · '),
            _score: searchable.indexOf(q),
          });
        }
      });
    } catch(e) {
      console.warn('search error for', type, e.message);
    }
  }));

  // Sort: exact matches first, then by score (lower = earlier occurrence = more relevant)
  allResults.sort((a, b) => {
    const aExact = String(a._title).toLowerCase() === q ? 0 : 1;
    const bExact = String(b._title).toLowerCase() === q ? 0 : 1;
    if (aExact !== bExact) return aExact - bExact;
    return a._score - b._score;
  });

  // Cap at 60 total results
  showGsResults(allResults.slice(0, 60));
}

// Recent searches (localStorage)
const LS_KEY = 'mednu_recent_searches';

function saveRecentSearch(query, resultTitle, resultType) {
  if (!query) return;
  try {
    let recent = JSON.parse(localStorage.getItem(LS_KEY) || '[]');
    recent = recent.filter(r => r.query !== query);
    recent.unshift({ query, resultTitle, resultType, ts: Date.now() });
    recent = recent.slice(0, 8);
    localStorage.setItem(LS_KEY, JSON.stringify(recent));
  } catch(e) {}
}

function clearRecentSearches() {
  try { localStorage.removeItem(LS_KEY); } catch(e) {}
  document.getElementById('gs-recent-wrap').style.display = 'none';
}

function loadRecentSearches() {
  try {
    const recent = JSON.parse(localStorage.getItem(LS_KEY) || '[]');
    const wrap = document.getElementById('gs-recent-wrap');
    const list = document.getElementById('gs-recent-list');
    if (!recent.length) { wrap.style.display = 'none'; return; }
    wrap.style.display = '';
    list.innerHTML = recent.map(r => {
      const cfg = GS_COLLECTIONS[r.resultType] || {};
      return `<div class="gs-recent-item" onclick="rerunSearch(${JSON.stringify(escHtml(r.query))})">
        <i class="ti ti-history"></i>
        <span style="flex:1;">${escHtml(r.query)}</span>
        <span style="font-size:11px;color:var(--text-muted);">${escHtml(cfg.label || r.resultType || '')}</span>
      </div>`;
    }).join('');
  } catch(e) {}
}

function rerunSearch(query) {
  const input = document.getElementById('gs-input');
  input.value = query;
  document.getElementById('gs-clear-btn').style.display = '';
  runSearch(query);
}

// ============================================
//   CAREGIVERS MANAGEMENT — FULL CRUD
// ============================================

let _allCaregivers      = [];
let _editingCaregiverId = null;
let _caregiversListener = null;

const CG_RATE_UNIT_LABELS = {
  per_day:   'Per Day',
  per_hour:  'Per Hour',
  per_week:  'Per Week',
  per_month: 'Per Month',
};

const CG_TYPE_COLORS = {
  Nurse:            { bg: '#e3f2fd', fg: '#1565c0' },
  Maid:             { bg: '#fce4ec', fg: '#c2185b' },
  Attendant:        { bg: '#e8f5e9', fg: '#2e7d32' },
  Physiotherapist:  { bg: '#fff3e0', fg: '#e65100' },
};

function initCaregiversListener() {
  if (_caregiversListener) _caregiversListener();
  _caregiversListener = db.collection('caregivers')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      _allCaregivers = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      filterCaregivers();
      const activeCount = _allCaregivers.filter(c => c.isActive).length;
      const badge = document.getElementById('nav-caregivers-count');
      if (badge) {
        badge.textContent = activeCount;
        badge.style.display = activeCount > 0 ? 'inline' : 'none';
      }
    }, err => console.error('[Caregivers]', err));
}

function filterCaregivers() {
  const q          = (document.getElementById('caregiver-search')?.value || '').toLowerCase();
  const typeFilter = document.getElementById('caregiver-type-filter')?.value || 'all';
  const genderFilter = document.getElementById('caregiver-gender-filter')?.value || 'all';
  const statusFilter = document.getElementById('caregiver-status-filter')?.value || 'all';

  let list = _allCaregivers;
  if (typeFilter !== 'all')   list = list.filter(c => c.type === typeFilter);
  if (genderFilter !== 'all') list = list.filter(c => c.gender === genderFilter);
  if (statusFilter === 'active')   list = list.filter(c => c.isActive);
  if (statusFilter === 'inactive') list = list.filter(c => !c.isActive);
  if (q) list = list.filter(c =>
    (c.name || '').toLowerCase().includes(q) ||
    (c.location || '').toLowerCase().includes(q) ||
    (c.specialty || '').toLowerCase().includes(q)
  );
  renderCaregiversList(list);
}

function renderCaregiversList(list) {
  const el = document.getElementById('caregivers-list');
  if (!el) return;
  if (!list.length) {
    el.innerHTML = '<div class="empty-state"><div class="empty-icon">🧑‍⚕️</div><p>No caregivers found. Add one above.</p></div>';
    return;
  }
  const rateUnitLabel = u => CG_RATE_UNIT_LABELS[u] || (u || 'Per Day');
  el.innerHTML = list.map(c => {
    const tc      = CG_TYPE_COLORS[c.type] || { bg: '#f3e5f5', fg: '#6a1b9a' };
    const rateStr = c.ratePerDay != null
      ? `₹${Number(c.ratePerDay).toLocaleString('en-IN')} <span style="font-size:11px;font-weight:400;color:var(--text-muted);">/ ${rateUnitLabel(c.rateUnit)}</span>`
      : '<span style="color:var(--text-muted);font-size:12px;">Rate not set</span>';
    const rating = c.rating ? `⭐ ${parseFloat(c.rating).toFixed(1)}` : '';
    return `
    <div class="service-card" id="cg-card-${c.id}">
      <div class="service-thumb-placeholder" style="background:${tc.bg};color:${tc.fg};font-size:22px;">🧑‍⚕️</div>
      <div class="service-info">
        <div class="service-name">${escHtml(c.name || '—')}</div>
        <div class="service-meta">
          ${escHtml(c.specialty || '')}
          ${c.experience ? ' · ' + escHtml(c.experience) : ''}
          ${c.location ? ' · 📍 ' + escHtml(c.location) : ''}
        </div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px;align-items:center;">
          <span class="svc-type-badge" style="background:${tc.bg};color:${tc.fg};">${escHtml(c.type || 'Caregiver')}</span>
          ${c.gender ? `<span class="svc-type-badge" style="background:#f3e5f5;color:#6a1b9a;">${escHtml(c.gender)}</span>` : ''}
          <span class="service-price">${rateStr}</span>
          ${rating ? `<span class="banner-cta-chip">${escHtml(rating)}</span>` : ''}
          ${c.isActive ? '<span class="pill pill-active">Active</span>' : '<span class="pill pill-suspended">Inactive</span>'}
        </div>
      </div>
      <div class="service-actions">
        <label class="toggle-label" title="${c.isActive ? 'Deactivate' : 'Activate'}">
          <input type="checkbox" ${c.isActive ? 'checked' : ''} onchange="toggleCaregiver('${c.id}', this.checked)" />
          <span class="toggle-switch"></span>
        </label>
        <button class="btn btn-outline" onclick="editCaregiver('${c.id}')" title="Edit">
          <i class="ti ti-edit"></i>
        </button>
        <button class="btn btn-reject" onclick="deleteCaregiver('${c.id}', this)" title="Delete">
          <i class="ti ti-trash"></i>
        </button>
      </div>
    </div>`;
  }).join('');
}

async function saveCaregiver() {
  const name       = document.getElementById('cg-name')?.value.trim();
  const type       = document.getElementById('cg-type')?.value;
  const gender     = document.getElementById('cg-gender')?.value;
  const location   = document.getElementById('cg-location')?.value.trim();
  const specialty  = document.getElementById('cg-specialty')?.value.trim();
  const experience = document.getElementById('cg-experience')?.value.trim();
  const rateRaw    = document.getElementById('cg-rate')?.value;
  const rateUnit   = document.getElementById('cg-rate-unit')?.value;
  const ratingRaw  = document.getElementById('cg-rating')?.value;
  const phone      = document.getElementById('cg-phone')?.value.trim();
  const bio        = document.getElementById('cg-bio')?.value.trim();
  const isActive   = document.getElementById('cg-active')?.checked !== false;

  if (!name)     { showToast('Name is required'); return; }
  if (!location) { showToast('Location is required'); return; }
  if (!rateRaw)  { showToast('Rate is required'); return; }

  const btn = document.getElementById('save-caregiver-btn');
  btn.disabled = true;

  // Build display rate string for the app
  const rateNum  = parseFloat(rateRaw);
  const unitMap  = { per_day: 'day', per_hour: 'hr', per_week: 'week', per_month: 'month' };
  const rateLabel = `₹${rateNum.toLocaleString('en-IN')}/${unitMap[rateUnit] || 'day'}`;

  const data = {
    name, type, gender, location,
    specialty:   specialty   || null,
    experience:  experience  || null,
    ratePerDay:  rateNum,
    rateUnit:    rateUnit    || 'per_day',
    rate:        rateLabel,
    rating:      ratingRaw   ? parseFloat(ratingRaw) : null,
    phone:       phone       || null,
    bio:         bio         || null,
    isActive,
    updatedAt:   firebase.firestore.FieldValue.serverTimestamp(),
    updatedBy:   auth.currentUser?.email || 'admin',
  };

  try {
    if (_editingCaregiverId) {
      await db.collection('caregivers').doc(_editingCaregiverId).update(data);
      showToast('Caregiver updated ✔');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('caregivers').add(data);
      showToast('Caregiver added ✔');
    }
    cancelCaregiverEdit();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    btn.disabled = false;
  }
}

function editCaregiver(id) {
  const c = _allCaregivers.find(x => x.id === id);
  if (!c) return;
  _editingCaregiverId = id;
  document.getElementById('cg-name').value        = c.name       || '';
  document.getElementById('cg-type').value        = c.type       || 'Nurse';
  document.getElementById('cg-gender').value      = c.gender     || 'Female';
  document.getElementById('cg-location').value    = c.location   || '';
  document.getElementById('cg-specialty').value   = c.specialty  || '';
  document.getElementById('cg-experience').value  = c.experience || '';
  document.getElementById('cg-rate').value        = c.ratePerDay != null ? c.ratePerDay : '';
  document.getElementById('cg-rate-unit').value   = c.rateUnit   || 'per_day';
  document.getElementById('cg-rating').value      = c.rating     != null ? c.rating : '';
  document.getElementById('cg-phone').value       = c.phone      || '';
  document.getElementById('cg-bio').value         = c.bio        || '';
  document.getElementById('cg-active').checked    = c.isActive   !== false;
  document.getElementById('caregiver-form-title').textContent = 'Edit Caregiver';
  document.getElementById('cancel-caregiver-btn').style.display = 'inline-flex';
  document.getElementById('cg-name').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function cancelCaregiverEdit() {
  _editingCaregiverId = null;
  ['cg-name','cg-location','cg-specialty','cg-experience','cg-rate','cg-rating','cg-phone','cg-bio']
    .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
  document.getElementById('cg-type').value        = 'Nurse';
  document.getElementById('cg-gender').value      = 'Female';
  document.getElementById('cg-rate-unit').value   = 'per_day';
  document.getElementById('cg-active').checked    = true;
  document.getElementById('caregiver-form-title').textContent = 'Add Caregiver';
  document.getElementById('cancel-caregiver-btn').style.display = 'none';
}

async function toggleCaregiver(id, isActive) {
  try {
    await db.collection('caregivers').doc(id).update({ isActive, updatedAt: firebase.firestore.FieldValue.serverTimestamp() });
  } catch (e) { showToast('Update failed: ' + e.message); }
}

async function deleteCaregiver(id, btn) {
  if (!confirm('Delete this caregiver? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    await db.collection('caregivers').doc(id).delete();
    showToast('Caregiver deleted');
  } catch (e) {
    showToast('Delete failed: ' + e.message);
    btn.disabled = false;
  }
}

// ============================================
//   CARE ASSISTANTS
// ============================================

let _allCareAssistants      = [];
let _editingCareAssistantId = null;
let _careAssistantsListener = null;

function initCareAssistantsListener() {
  if (_careAssistantsListener) _careAssistantsListener();
  _careAssistantsListener = db.collection('care_assistants')
    .orderBy('createdAt', 'desc')
    .onSnapshot(snap => {
      _allCareAssistants = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      filterCareAssistants();
      const activeCount = _allCareAssistants.filter(c => c.isActive).length;
      const badge = document.getElementById('nav-care-assistants-count');
      if (badge) {
        badge.textContent = activeCount;
        badge.style.display = activeCount > 0 ? 'inline' : 'none';
      }
    }, err => console.error('[CareAssistants]', err));
}

function filterCareAssistants() {
  const q            = (document.getElementById('care-assistant-search')?.value || '').toLowerCase();
  const genderFilter  = document.getElementById('care-assistant-gender-filter')?.value || 'all';
  const statusFilter  = document.getElementById('care-assistant-status-filter')?.value || 'all';

  let list = _allCareAssistants;
  if (genderFilter !== 'all') list = list.filter(c => c.gender === genderFilter);
  if (statusFilter === 'active')   list = list.filter(c => c.isActive);
  if (statusFilter === 'inactive') list = list.filter(c => !c.isActive);
  if (q) list = list.filter(c =>
    (c.name || '').toLowerCase().includes(q) ||
    (c.location || '').toLowerCase().includes(q) ||
    (c.specialty || '').toLowerCase().includes(q)
  );
  renderCareAssistantsList(list);
}

function renderCareAssistantsList(list) {
  const el = document.getElementById('care-assistants-list');
  if (!el) return;
  if (!list.length) {
    el.innerHTML = '<div class="empty-state"><div class="empty-icon">🧑‍🦽</div><p>No care assistants found. Add one above.</p></div>';
    return;
  }
  el.innerHTML = list.map(c => {
    const tc = { bg: '#fff3e0', fg: '#e65100' };
    const rating = c.rating ? `⭐ ${parseFloat(c.rating).toFixed(1)}` : '';
    return `
    <div class="service-card" id="ca-card-${c.id}">
      <div class="service-thumb-placeholder" style="background:${tc.bg};color:${tc.fg};font-size:22px;">🧑‍🦽</div>
      <div class="service-info">
        <div class="service-name">${escHtml(c.name || '—')}</div>
        <div class="service-meta">
          ${escHtml(c.specialty || '')}
          ${c.experience ? ' · ' + escHtml(c.experience) : ''}
          ${c.location ? ' · 📍 ' + escHtml(c.location) : ''}
        </div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px;align-items:center;">
          ${c.gender ? `<span class="svc-type-badge" style="background:#f3e5f5;color:#6a1b9a;">${escHtml(c.gender)}</span>` : ''}
          <span class="service-price">₹${Number(c.rateHourly || 0).toLocaleString('en-IN')}<span style="font-size:11px;font-weight:400;color:var(--text-muted);">/hr</span></span>
          <span class="service-price">₹${Number(c.rateFullDay || 0).toLocaleString('en-IN')}<span style="font-size:11px;font-weight:400;color:var(--text-muted);">/day</span></span>
          ${c.isVerified ? '<span class="svc-type-badge" style="background:#e8f5e9;color:#2e7d32;">Verified</span>' : ''}
          ${rating ? `<span class="banner-cta-chip">${escHtml(rating)}</span>` : ''}
          ${c.isActive ? '<span class="pill pill-active">Active</span>' : '<span class="pill pill-suspended">Inactive</span>'}
        </div>
      </div>
      <div class="service-actions">
        <label class="toggle-label" title="${c.isActive ? 'Deactivate' : 'Activate'}">
          <input type="checkbox" ${c.isActive ? 'checked' : ''} onchange="toggleCareAssistant('${c.id}', this.checked)" />
          <span class="toggle-switch"></span>
        </label>
        <button class="btn btn-outline" onclick="editCareAssistant('${c.id}')" title="Edit">
          <i class="ti ti-edit"></i>
        </button>
        <button class="btn btn-reject" onclick="deleteCareAssistant('${c.id}', this)" title="Delete">
          <i class="ti ti-trash"></i>
        </button>
      </div>
    </div>`;
  }).join('');
}

async function saveCareAssistant() {
  const name          = document.getElementById('ca-name')?.value.trim();
  const gender        = document.getElementById('ca-gender')?.value;
  const location      = document.getElementById('ca-location')?.value.trim();
  const specialty     = document.getElementById('ca-specialty')?.value.trim();
  const experience    = document.getElementById('ca-experience')?.value.trim();
  const rateHourlyRaw  = document.getElementById('ca-rate-hourly')?.value;
  const rateHalfDayRaw = document.getElementById('ca-rate-halfday')?.value;
  const rateFullDayRaw = document.getElementById('ca-rate-fullday')?.value;
  const rateMultiDayRaw = document.getElementById('ca-rate-multiday')?.value;
  const ratingRaw     = document.getElementById('ca-rating')?.value;
  const phone         = document.getElementById('ca-phone')?.value.trim();
  const bio           = document.getElementById('ca-bio')?.value.trim();
  const isVerified    = document.getElementById('ca-verified')?.checked !== false;
  const isActive      = document.getElementById('ca-active')?.checked !== false;

  if (!name)     { showToast('Name is required'); return; }
  if (!location) { showToast('Location is required'); return; }
  if (!rateHourlyRaw || !rateHalfDayRaw || !rateFullDayRaw || !rateMultiDayRaw) {
    showToast('All four duration rates are required'); return;
  }

  const btn = document.getElementById('save-care-assistant-btn');
  btn.disabled = true;

  const data = {
    name, gender, location,
    specialty:     specialty  || null,
    experience:    experience || null,
    rateHourly:    parseFloat(rateHourlyRaw),
    rateHalfDay:   parseFloat(rateHalfDayRaw),
    rateFullDay:   parseFloat(rateFullDayRaw),
    rateMultiDay:  parseFloat(rateMultiDayRaw),
    rating:        ratingRaw ? parseFloat(ratingRaw) : null,
    phone:         phone     || null,
    bio:           bio       || null,
    isVerified,
    isActive,
    updatedAt:     firebase.firestore.FieldValue.serverTimestamp(),
    updatedBy:     auth.currentUser?.email || 'admin',
  };

  try {
    if (_editingCareAssistantId) {
      await db.collection('care_assistants').doc(_editingCareAssistantId).update(data);
      showToast('Care assistant updated ✔');
    } else {
      data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      await db.collection('care_assistants').add(data);
      showToast('Care assistant added ✔');
    }
    cancelCareAssistantEdit();
  } catch (err) {
    showToast('Save failed: ' + err.message);
  } finally {
    btn.disabled = false;
  }
}

function editCareAssistant(id) {
  const c = _allCareAssistants.find(x => x.id === id);
  if (!c) return;
  _editingCareAssistantId = id;
  document.getElementById('ca-name').value           = c.name         || '';
  document.getElementById('ca-gender').value         = c.gender       || 'Male';
  document.getElementById('ca-location').value       = c.location     || '';
  document.getElementById('ca-specialty').value      = c.specialty    || '';
  document.getElementById('ca-experience').value     = c.experience   || '';
  document.getElementById('ca-rate-hourly').value    = c.rateHourly   != null ? c.rateHourly   : '';
  document.getElementById('ca-rate-halfday').value   = c.rateHalfDay  != null ? c.rateHalfDay  : '';
  document.getElementById('ca-rate-fullday').value   = c.rateFullDay  != null ? c.rateFullDay  : '';
  document.getElementById('ca-rate-multiday').value  = c.rateMultiDay != null ? c.rateMultiDay : '';
  document.getElementById('ca-rating').value         = c.rating       != null ? c.rating       : '';
  document.getElementById('ca-phone').value          = c.phone        || '';
  document.getElementById('ca-bio').value            = c.bio          || '';
  document.getElementById('ca-verified').checked     = c.isVerified   !== false;
  document.getElementById('ca-active').checked       = c.isActive     !== false;
  document.getElementById('care-assistant-form-title').textContent = 'Edit Care Assistant';
  document.getElementById('cancel-care-assistant-btn').style.display = 'inline-flex';
  document.getElementById('ca-name').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function cancelCareAssistantEdit() {
  _editingCareAssistantId = null;
  ['ca-name','ca-location','ca-specialty','ca-experience','ca-rate-hourly','ca-rate-halfday','ca-rate-fullday','ca-rate-multiday','ca-rating','ca-phone','ca-bio']
    .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
  document.getElementById('ca-gender').value      = 'Male';
  document.getElementById('ca-verified').checked  = true;
  document.getElementById('ca-active').checked    = true;
  document.getElementById('care-assistant-form-title').textContent = 'Add Care Assistant';
  document.getElementById('cancel-care-assistant-btn').style.display = 'none';
}

async function toggleCareAssistant(id, isActive) {
  try {
    await db.collection('care_assistants').doc(id).update({ isActive, updatedAt: firebase.firestore.FieldValue.serverTimestamp() });
  } catch (e) { showToast('Update failed: ' + e.message); }
}

async function deleteCareAssistant(id, btn) {
  if (!confirm('Delete this care assistant? This cannot be undone.')) return;
  btn.disabled = true;
  try {
    await db.collection('care_assistants').doc(id).delete();
    showToast('Care assistant deleted');
  } catch (e) {
    showToast('Delete failed: ' + e.message);
    btn.disabled = false;
  }
}

