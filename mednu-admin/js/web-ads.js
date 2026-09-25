/* Web Ads — manages the ad slot shown in the middle of the public website
   (mednu-web landing page). Separate from app "Banners". Uses the `web_ads`
   collection; the website reads enabled ads live and hides the slot (no gap)
   when none is live. Relies on globals from app.js/firebase-config.js:
   db, storage, auth, showToast, escHtml, formatDate. */
(function () {
  let editingId = null;
  let ads = [];
  let unsub = null;

  const $ = id => document.getElementById(id);

  function status(a) {
    const now = Date.now();
    const s = a.startDate?.toMillis ? a.startDate.toMillis() : null;
    const e = a.endDate?.toMillis ? a.endDate.toMillis() : null;
    if (!a.isEnabled) return { cls: 'pill-suspended', label: 'Disabled' };
    if (s && now < s) return { cls: 'pill-scheduled', label: 'Scheduled' };
    if (e && now >= e) return { cls: 'pill-expired', label: 'Expired' };
    return { cls: 'pill-active', label: 'Live on website' };
  }

  function render() {
    const el = $('web-ads-list');
    if (!el) return;
    const filter = $('web-ad-filter')?.value || 'all';
    const rows = ads.filter(a => {
      const st = status(a).label;
      return filter === 'all' || (filter === 'live' && st === 'Live on website') ||
        (filter === 'disabled' && st === 'Disabled') || (filter === 'scheduled' && st === 'Scheduled') ||
        (filter === 'expired' && st === 'Expired');
    });
    const live = ads.filter(a => status(a).label === 'Live on website').length;
    const badge = $('nav-web-ad-count');
    if (badge) { badge.textContent = live; badge.style.display = live ? '' : 'none'; }

    if (!rows.length) {
      el.innerHTML = '<div class="empty-state"><div class="empty-icon"><i class="ti ti-ad-2"></i></div><p>No ads yet — the website ad area stays hidden until you publish one.</p></div>';
      return;
    }
    el.innerHTML = rows.map(a => {
      const st = status(a);
      const range = (a.startDate || a.endDate)
        ? `${a.startDate ? formatDate(a.startDate) : 'Anytime'} → ${a.endDate ? formatDate(a.endDate) : 'No end date'}`
        : 'No date restriction';
      const thumb = a.imageUrl
        ? `<img class="banner-thumb" src="${escHtml(a.imageUrl)}" alt="Ad" loading="lazy" />`
        : '<div class="banner-thumb-placeholder"><i class="ti ti-photo"></i></div>';
      return `
      <div class="banner-card">
        ${thumb}
        <div class="banner-info">
          <div class="banner-name">${a.title ? escHtml(a.title) : '<em style="color:var(--text-muted)">Untitled ad</em>'}</div>
          <div class="banner-meta">${range}</div>
          ${a.linkUrl ? `<span class="banner-cta-chip">Link: ${escHtml(a.linkUrl.slice(0, 48))}</span>` : ''}
          <div style="margin-top:6px;"><span class="pill ${st.cls}">${st.label}</span></div>
        </div>
        <div class="banner-actions">
          <label class="toggle-label" title="${a.isEnabled ? 'Click to disable' : 'Click to enable'}">
            <input type="checkbox" ${a.isEnabled ? 'checked' : ''} onchange="toggleWebAd('${a.id}', this.checked)" />
            <span class="toggle-switch"></span>
          </label>
          <button class="btn btn-outline" onclick="editWebAd('${a.id}')"><i class="ti ti-edit"></i></button>
          <button class="btn btn-outline" style="color:#c0392b;" onclick="deleteWebAd('${a.id}')"><i class="ti ti-trash"></i></button>
        </div>
      </div>`;
    }).join('');
  }

  function start() {
    if (unsub) return;
    unsub = db.collection('web_ads').orderBy('createdAt', 'desc').onSnapshot(snap => {
      ads = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      render();
    }, err => {
      const el = $('web-ads-list');
      if (el) el.innerHTML = '<div class="empty-state"><p>Could not load ads (' + escHtml(err.code || 'error') + ').</p></div>';
    });
  }
  auth.onAuthStateChanged(u => { if (u) start(); });
  document.addEventListener('change', e => { if (e.target && e.target.id === 'web-ad-filter') render(); });
  setInterval(render, 60000); // keep Scheduled / Expired badges current

  function toLocalInput(ts) {
    if (!ts || !ts.toDate) return '';
    const d = ts.toDate();
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  window.previewWebAdImage = function (ev) {
    const f = ev.target.files[0];
    if (!f) return;
    if (f.size > 5 * 1024 * 1024) { showToast('Image must be under 5 MB'); ev.target.value = ''; return; }
    const img = $('web-ad-preview-img');
    img.src = URL.createObjectURL(f);
    img.style.display = 'block';
    $('web-ad-upload-placeholder').style.display = 'none';
    $('web-ad-remove-img').style.display = 'flex';
  };

  window.removeWebAdImage = function (ev) {
    if (ev) ev.stopPropagation();
    $('web-ad-file-input').value = '';
    $('web-ad-preview-img').style.display = 'none';
    $('web-ad-upload-placeholder').style.display = '';
    $('web-ad-remove-img').style.display = 'none';
  };

  function resetForm() {
    editingId = null;
    ['web-ad-title', 'web-ad-link', 'web-ad-start', 'web-ad-end'].forEach(i => { $(i).value = ''; });
    $('web-ad-enabled').checked = true;
    removeWebAdImage();
    $('web-ad-form-title').textContent = 'Create New Ad';
    $('cancel-web-ad-btn').style.display = 'none';
    $('publish-web-ad-btn').innerHTML = '<i class="ti ti-upload"></i> Publish Ad';
  }
  window.cancelWebAdEdit = resetForm;

  window.editWebAd = function (id) {
    const a = ads.find(x => x.id === id);
    if (!a) return;
    editingId = id;
    $('web-ad-title').value = a.title || '';
    $('web-ad-link').value = a.linkUrl || '';
    $('web-ad-start').value = toLocalInput(a.startDate);
    $('web-ad-end').value = toLocalInput(a.endDate);
    $('web-ad-enabled').checked = !!a.isEnabled;
    if (a.imageUrl) {
      const img = $('web-ad-preview-img');
      img.src = a.imageUrl;
      img.style.display = 'block';
      $('web-ad-upload-placeholder').style.display = 'none';
      $('web-ad-remove-img').style.display = 'flex';
    }
    $('web-ad-form-title').textContent = 'Edit Ad';
    $('cancel-web-ad-btn').style.display = '';
    $('publish-web-ad-btn').innerHTML = '<i class="ti ti-check"></i> Save Changes';
    $('tab-web-ads').scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  window.toggleWebAd = async function (id, on) {
    try {
      await db.collection('web_ads').doc(id).update({
        isEnabled: on,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      showToast(on ? 'Ad enabled' : 'Ad disabled');
    } catch (e) { showToast('Update failed: ' + e.message); }
  };

  window.deleteWebAd = async function (id) {
    if (!confirm('Delete this ad permanently? It will disappear from the website immediately.')) return;
    const a = ads.find(x => x.id === id);
    try {
      await db.collection('web_ads').doc(id).delete();
      if (a && a.storagePath) { try { await storage.ref(a.storagePath).delete(); } catch (_) {} }
      showToast('Ad deleted');
      if (editingId === id) resetForm();
    } catch (e) { showToast('Delete failed: ' + e.message); }
  };

  window.publishWebAd = async function () {
    const title = $('web-ad-title').value.trim();
    let link = $('web-ad-link').value.trim();
    const startVal = $('web-ad-start').value;
    const endVal = $('web-ad-end').value;
    const file = $('web-ad-file-input').files[0];
    const btn = $('publish-web-ad-btn');
    const prog = $('web-ad-upload-progress');

    if (!editingId && !file) { showToast('Please select an ad image'); return; }
    if (link && !/^https?:\/\//i.test(link)) link = 'https://' + link;
    if (startVal && endVal && new Date(startVal) >= new Date(endVal)) { showToast('End date must be after start date'); return; }

    btn.disabled = true;
    let imageUrl = '', storagePath = '';
    if (editingId && !file) {
      const ex = ads.find(x => x.id === editingId);
      imageUrl = ex?.imageUrl || '';
      storagePath = ex?.storagePath || '';
    }
    if (file) {
      prog.style.display = 'flex';
      btn.style.display = 'none';
      storagePath = `web_ads/${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
      const ref = storage.ref(storagePath);
      try {
        await new Promise((res, rej) => ref.put(file, { contentType: file.type }).on('state_changed', null, rej, res));
        imageUrl = await ref.getDownloadURL();
      } catch (e) {
        showToast('Upload failed: ' + e.message);
        prog.style.display = 'none'; btn.style.display = 'inline-flex'; btn.disabled = false;
        return;
      }
      prog.style.display = 'none';
      btn.style.display = 'inline-flex';
    }

    const T = firebase.firestore.Timestamp;
    const data = {
      title: title || null,
      linkUrl: link || null,
      imageUrl,
      storagePath,
      isEnabled: $('web-ad-enabled').checked,
      startDate: startVal ? T.fromDate(new Date(startVal)) : null,
      endDate: endVal ? T.fromDate(new Date(endVal)) : null,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      createdBy: auth.currentUser?.email || 'admin',
    };
    try {
      if (editingId) {
        await db.collection('web_ads').doc(editingId).update(data);
        showToast('Ad updated ✓');
      } else {
        data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        await db.collection('web_ads').add(data);
        showToast('Ad published ✓ — live on the website now');
      }
      resetForm();
    } catch (e) {
      showToast('Save failed: ' + e.message);
    } finally {
      btn.disabled = false;
    }
  };
})();
