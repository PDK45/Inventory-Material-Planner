/**
 * MPPMS Voice Command Engine — 34_voice_engine.js
 * Paste this entire file into:
 *   APEX Page 150 → Page Attributes → JavaScript → Function and Global Variable Declaration
 *
 * How it works:
 *  1. User clicks the mic FAB button
 *  2. Web Speech API records speech and produces a transcript
 *  3. NLP parser classifies intent (QUERY / RECEIPT / ADJUST)
 *  4. For queries: calls ORDS API, speaks result aloud
 *  5. For transactions: shows confirm modal → calls ORDS API on confirm
 */

/* ── GLOBAL STATE ─────────────────────────────────────────── */
var VC = {
  recognition : null,
  synth       : window.speechSynthesis,
  listening   : false,
  materials   : [],   // loaded from DB on init
  warehouses  : [],
  bins        : [],
  baseUrl     : 'http://localhost:8080/ords/mppms/api',
  pendingIntent: null
};

/* ── BOOT: load lookup data once ─────────────────────────── */
function vcInit() {
  // Load materials
  fetch('http://localhost:8080/ords/mppms/api/materials')
    .then(r => r.json())
    .then(d => { VC.materials = d.items || []; })
    .catch(() => {});

  // Load warehouses
  fetch('http://localhost:8080/ords/mppms/api/inventory/warehouses')
    .then(r => r.json())
    .then(d => { VC.warehouses = d.items || []; })
    .catch(() => {});

  vcInjectUI();
}

/* ── UI INJECTION ─────────────────────────────────────────── */
function vcInjectUI() {
  if (document.getElementById('vc-fab')) return;

  document.body.insertAdjacentHTML('beforeend', `
    <!-- Voice FAB -->
    <button id="vc-fab" onclick="vcStart()" title="Voice Command">
      <span id="vc-fab-icon">🎤</span>
    </button>

    <!-- Listening Overlay -->
    <div id="vc-overlay" style="display:none;">
      <div id="vc-panel">
        <div id="vc-waves">
          <span></span><span></span><span></span><span></span><span></span>
        </div>
        <p id="vc-transcript">Listening...</p>
        <button onclick="vcStop()">■ Stop</button>
      </div>
    </div>

    <!-- Confirm Modal -->
    <div id="vc-modal" style="display:none;">
      <div id="vc-modal-card">
        <h3>🎙️ Voice Command Detected</h3>
        <div id="vc-modal-body"></div>
        <div id="vc-modal-actions">
          <button id="vc-btn-confirm" onclick="vcExecute()">✅ Confirm &amp; Post</button>
          <button onclick="vcCancel()">❌ Cancel</button>
        </div>
      </div>
    </div>

    <style>
      #vc-fab {
        position:fixed; bottom:28px; right:28px; z-index:9999;
        width:60px; height:60px; border-radius:50%; border:none; cursor:pointer;
        background:linear-gradient(135deg,#1565C0,#0D47A1);
        color:#fff; font-size:26px; box-shadow:0 4px 20px rgba(21,101,192,.6);
        transition:transform .2s,box-shadow .2s;
      }
      #vc-fab:hover { transform:scale(1.1); box-shadow:0 6px 28px rgba(21,101,192,.8); }
      #vc-fab.listening { animation:vcPulse 1s infinite; background:linear-gradient(135deg,#c62828,#b71c1c); }
      @keyframes vcPulse { 0%,100%{transform:scale(1)} 50%{transform:scale(1.12)} }

      #vc-overlay {
        position:fixed; inset:0; z-index:9998;
        background:rgba(0,0,0,.55); display:flex; align-items:center; justify-content:center;
      }
      #vc-panel {
        background:#0d1527; border:1px solid rgba(255,255,255,.12); border-radius:20px;
        padding:40px 50px; text-align:center; color:#f8fafc; min-width:360px;
        box-shadow:0 12px 60px rgba(0,0,0,.6);
      }
      #vc-waves { display:flex; gap:6px; justify-content:center; margin-bottom:24px; height:50px; align-items:center; }
      #vc-waves span {
        width:6px; border-radius:4px; background:#3b82f6;
        animation:vcWave 0.9s ease-in-out infinite;
      }
      #vc-waves span:nth-child(1){height:20px;animation-delay:0s}
      #vc-waves span:nth-child(2){height:35px;animation-delay:.1s}
      #vc-waves span:nth-child(3){height:50px;animation-delay:.2s}
      #vc-waves span:nth-child(4){height:35px;animation-delay:.3s}
      #vc-waves span:nth-child(5){height:20px;animation-delay:.4s}
      @keyframes vcWave { 0%,100%{transform:scaleY(1)} 50%{transform:scaleY(1.5)} }
      #vc-transcript { font-size:1.1rem; margin-bottom:24px; color:#94a3b8; min-height:32px; }
      #vc-panel button { padding:10px 28px; border-radius:8px; border:none; cursor:pointer;
        background:#ef4444; color:#fff; font-size:.95rem; font-weight:600; }

      #vc-modal {
        position:fixed; inset:0; z-index:10000;
        background:rgba(0,0,0,.65); display:flex; align-items:center; justify-content:center;
      }
      #vc-modal-card {
        background:#0d1527; border:1px solid rgba(255,255,255,.12); border-radius:20px;
        padding:36px 44px; color:#f8fafc; min-width:400px; max-width:520px;
        box-shadow:0 16px 60px rgba(0,0,0,.7);
      }
      #vc-modal-card h3 { margin-bottom:24px; font-size:1.2rem; color:#60a5fa; }
      #vc-modal-body { background:rgba(255,255,255,.04); border-radius:12px;
        padding:20px; margin-bottom:28px; font-size:.95rem; line-height:1.9; }
      #vc-modal-body strong { color:#93c5fd; }
      #vc-modal-actions { display:flex; gap:14px; }
      #vc-btn-confirm { flex:1; padding:12px; border-radius:10px; border:none; cursor:pointer;
        background:linear-gradient(135deg,#10b981,#065f46); color:#fff; font-size:1rem; font-weight:700; }
      #vc-modal-actions button:last-child { flex:1; padding:12px; border-radius:10px; border:none;
        cursor:pointer; background:rgba(239,68,68,.15); color:#ef4444;
        border:1px solid rgba(239,68,68,.3); font-size:1rem; font-weight:600; }
    </style>
  `);
}

/* ── SPEECH RECOGNITION ───────────────────────────────────── */
function vcStart() {
  if (!('webkitSpeechRecognition' in window || 'SpeechRecognition' in window)) {
    vcSpeak('Sorry, your browser does not support voice commands. Please use Chrome or Edge.');
    return;
  }

  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  VC.recognition = new SR();
  VC.recognition.lang = 'en-US';
  VC.recognition.continuous = false;
  VC.recognition.interimResults = true;

  VC.recognition.onstart = function() {
    VC.listening = true;
    document.getElementById('vc-fab').classList.add('listening');
    document.getElementById('vc-fab-icon').textContent = '🔴';
    document.getElementById('vc-overlay').style.display = 'flex';
    document.getElementById('vc-transcript').textContent = 'Listening...';
  };

  VC.recognition.onresult = function(e) {
    var transcript = '';
    for (var i = e.resultIndex; i < e.results.length; i++) {
      transcript += e.results[i][0].transcript;
    }
    document.getElementById('vc-transcript').textContent = transcript;
  };

  VC.recognition.onend = function() {
    var t = document.getElementById('vc-transcript').textContent;
    vcStop();
    if (t && t !== 'Listening...') vcParseIntent(t.toLowerCase().trim());
  };

  VC.recognition.onerror = function(e) {
    vcStop();
    vcShowToast('Microphone error: ' + e.error, 'error');
  };

  VC.recognition.start();
}

function vcStop() {
  VC.listening = false;
  if (VC.recognition) { try { VC.recognition.stop(); } catch(e){} }
  document.getElementById('vc-fab').classList.remove('listening');
  document.getElementById('vc-fab-icon').textContent = '🎤';
  document.getElementById('vc-overlay').style.display = 'none';
}

/* ── NLP INTENT PARSER ────────────────────────────────────── */
function vcParseIntent(text) {
  // --- STOCK QUERY ---
  if (/how much|stock of|how many|quantity of|check stock|available/.test(text)) {
    var keyword = vcExtractMaterialKeyword(text);
    if (keyword) { vcQueryStock(keyword); return; }
  }

  // --- GOODS RECEIPT ---
  if (/received|receipt|goods receipt|incoming|receive/.test(text)) {
    var intent = vcExtractReceiptIntent(text);
    if (intent) { vcShowConfirm(intent); return; }
  }

  // --- STOCK ADJUST ---
  if (/adjust|set stock|update stock|correct|physical count/.test(text)) {
    var intent = vcExtractAdjustIntent(text);
    if (intent) { vcShowConfirm(intent); return; }
  }

  vcShowToast('Could not understand: "' + text + '". Try: "how much H-Beams" or "400 MT H-Beams received"', 'warning');
}

function vcExtractMaterialKeyword(text) {
  // Strip common filler words
  var clean = text
    .replace(/how much|how many|stock of|quantity of|check stock|available|do we have|is there/g, '')
    .replace(/\?/g, '').trim();
  return clean.length > 2 ? clean : null;
}

function vcExtractReceiptIntent(text) {
  // Pattern: "[qty] [uom] [material keywords] received [in warehouse X] [bin Y]"
  var qtyMatch  = text.match(/(\d+(?:\.\d+)?)/);
  var uomMatch  = text.match(/\b(mt|kg|set|sft|ltr|ea|roll|pcs|ton|tons)\b/i);
  var whMatch   = text.match(/warehouse[\s-]*([\w-]+)/i) || text.match(/\b(wh-[\w-]+)/i);
  var binMatch  = text.match(/bin[\s-]*([\w-]+)/i);

  if (!qtyMatch) return null;

  var keyword = text
    .replace(/\d+(?:\.\d+)?/g,'')
    .replace(/mt|kg|set|sft|ltr|ea|roll|pcs|ton|tons/gi,'')
    .replace(/received|receipt|goods receipt|incoming|receive|warehouse[\s\w-]*/gi,'')
    .replace(/bin[\s\w-]*/gi,'').trim();

  return {
    action    : 'GOODS_RECEIPT',
    quantity  : parseFloat(qtyMatch[1]),
    uom       : uomMatch ? uomMatch[1].toUpperCase() : null,
    keyword   : keyword,
    warehouse : whMatch ? whMatch[1] : null,
    bin       : binMatch ? binMatch[1] : null
  };
}

function vcExtractAdjustIntent(text) {
  var qtyMatch = text.match(/(\d+(?:\.\d+)?)/);
  if (!qtyMatch) return null;
  var keyword = text
    .replace(/adjust|set stock|update stock|correct|physical count|to\s+\d+/gi,'')
    .replace(/\d+(?:\.\d+)?/g,'').trim();
  return {
    action   : 'STOCK_ADJUST',
    quantity : parseFloat(qtyMatch[1]),
    keyword  : keyword,
    warehouse: null,
    bin      : null
  };
}

/* ── FUZZY MATERIAL SEARCH ────────────────────────────────── */
function vcFuzzyMatch(keyword, list) {
  if (!list || !list.length) return null;
  var kw = keyword.toLowerCase();
  var scored = list.map(function(m) {
    var name = (m.material_name || m.name || '').toLowerCase();
    var code = (m.material_code || m.code || '').toLowerCase();
    var score = 0;
    kw.split(' ').forEach(function(w) {
      if (w.length < 2) return;
      if (name.includes(w)) score += 3;
      if (code.includes(w)) score += 2;
    });
    return { item: m, score: score };
  });
  scored.sort(function(a,b){ return b.score - a.score; });
  return scored[0] && scored[0].score > 0 ? scored[0].item : null;
}

/* ── STOCK QUERY ─────────────────────────────────────────── */
function vcQueryStock(keyword) {
  vcShowToast('Searching for: ' + keyword + '...', 'info');
  fetch(VC.baseUrl + '/voice/stock?search=' + encodeURIComponent(keyword))
    .then(function(r){ return r.json(); })
    .then(function(data) {
      var items = data.items || [];
      if (!items.length) {
        vcSpeak('No material found matching ' + keyword);
        vcShowToast('No material found for: ' + keyword, 'warning');
        return;
      }
      var m = items[0];
      var msg = m.material_name + ': ' +
        m.qty_on_hand + ' ' + m.uom +
        ' on hand. Status: ' + (m.stock_status || 'Unknown') +
        '. Warehouse: ' + (m.warehouse_code || 'N/A') + '.';
      vcSpeak(msg);
      vcShowToast('📦 ' + m.material_code + ': ' + m.qty_on_hand + ' ' + m.uom + ' (' + (m.stock_status||'N/A') + ')', 'info', 6000);
    })
    .catch(function() {
      // Fallback to APEX page data if ORDS offline
      vcSpeak('Could not reach the database. Please check your connection.');
    });
}

/* ── CONFIRM MODAL ────────────────────────────────────────── */
function vcShowConfirm(intent) {
  // Attempt fuzzy match if we have loaded materials
  var matched = vcFuzzyMatch(intent.keyword, VC.materials);
  intent.matched_material = matched;

  var matName = matched ? matched.material_name || matched.name : '⚠️ Unknown — "' + intent.keyword + '"';
  var matCode = matched ? matched.material_code || matched.code : '?';

  var actionLabel = intent.action === 'GOODS_RECEIPT' ? 'Goods Receipt (MIGO 101)' : 'Stock Adjustment (MIGO 551)';

  document.getElementById('vc-modal-body').innerHTML =
    '<p><strong>Action:</strong> '   + actionLabel + '</p>' +
    '<p><strong>Material:</strong> ' + matCode + ' — ' + matName + '</p>' +
    '<p><strong>Quantity:</strong> ' + intent.quantity + ' ' + (intent.uom || '') + '</p>' +
    (intent.warehouse ? '<p><strong>Warehouse:</strong> ' + intent.warehouse + '</p>' : '') +
    (intent.bin       ? '<p><strong>Bin:</strong> '       + intent.bin + '</p>'       : '') +
    (!matched ? '<p style="color:#f59e0b;margin-top:12px;">⚠️ Material not matched exactly. Please verify before confirming.</p>' : '');

  VC.pendingIntent = intent;
  document.getElementById('vc-modal').style.display = 'flex';
}

function vcCancel() {
  document.getElementById('vc-modal').style.display = 'none';
  VC.pendingIntent = null;
}

/* ── EXECUTE CONFIRMED INTENT ─────────────────────────────── */
function vcExecute() {
  var intent = VC.pendingIntent;
  if (!intent) return;
  vcCancel();

  var mat = intent.matched_material;
  if (!mat) {
    vcShowToast('Cannot execute — material not identified. Please try again with the exact material code.', 'error');
    return;
  }

  // Resolve warehouse/bin IDs
  var whId  = vcResolveWarehouse(intent.warehouse);
  var binId = vcResolveBin(intent.bin, whId);

  if (!whId || !binId) {
    // Default to first available warehouse/bin if not spoken
    whId  = VC.warehouses.length ? VC.warehouses[0].warehouse_id : 101;
    binId = VC.bins.length       ? VC.bins[0].bin_id             : 501;
  }

  var url, body;
  if (intent.action === 'GOODS_RECEIPT') {
    url  = VC.baseUrl + '/voice/receipt';
    body = { material_id: mat.material_id || mat.id, warehouse_id: whId, bin_id: binId,
             quantity: intent.quantity, po_id: null, performed_by: 'VOICE_CMD',
             remarks: 'Posted via MPPMS Voice Command' };
  } else {
    url  = VC.baseUrl + '/voice/adjust';
    body = { material_id: mat.material_id || mat.id, warehouse_id: whId, bin_id: binId,
             new_quantity: intent.quantity, performed_by: 'VOICE_CMD',
             remarks: 'Adjusted via MPPMS Voice Command' };
  }

  document.getElementById('vc-btn-confirm').disabled = true;

  fetch(url, {
    method : 'POST',
    headers: { 'Content-Type': 'application/json' },
    body   : JSON.stringify(body)
  })
  .then(function(r){ return r.json(); })
  .then(function(res) {
    if (res.status === 'SUCCESS' || res.x01 === 'SUCCESS') {
      var doneMsg = 'Done. ' + intent.quantity + ' ' + (intent.uom || 'units') +
        ' of ' + (mat.material_name || mat.name) + ' posted successfully.';
      vcSpeak(doneMsg);
      vcShowToast('✅ ' + doneMsg, 'success', 5000);
      // Refresh APEX page regions
      if (typeof apex !== 'undefined' && apex.region) {
        try { apex.region('stock-report').refresh(); } catch(e) {}
      }
    } else {
      vcSpeak('Transaction failed. ' + (res.message || ''));
      vcShowToast('❌ Error: ' + (res.message || 'Unknown error'), 'error');
    }
  })
  .catch(function(e) {
    vcSpeak('Network error. Please check your connection.');
    vcShowToast('❌ Network error: ' + e.message, 'error');
  });
}

/* ── HELPERS ──────────────────────────────────────────────── */
function vcResolveWarehouse(spoken) {
  if (!spoken || !VC.warehouses.length) return null;
  var s = spoken.toLowerCase();
  var found = VC.warehouses.find(function(w) {
    return (w.warehouse_code||'').toLowerCase().includes(s) ||
           (w.warehouse_name||'').toLowerCase().includes(s);
  });
  return found ? found.warehouse_id : null;
}

function vcResolveBin(spoken, warehouseId) {
  if (!spoken || !VC.bins.length) return null;
  var s = spoken.toLowerCase();
  var found = VC.bins.find(function(b) {
    return (b.bin_code||'').toLowerCase().includes(s) &&
           (!warehouseId || b.warehouse_id === warehouseId);
  });
  return found ? found.bin_id : null;
}

function vcSpeak(text) {
  if (!VC.synth) return;
  VC.synth.cancel();
  var utt = new SpeechSynthesisUtterance(text);
  utt.lang = 'en-US';
  utt.rate = 0.95;
  VC.synth.speak(utt);
}

function vcShowToast(message, type, duration) {
  var toast = document.createElement('div');
  var colors = { success:'#10b981', error:'#ef4444', warning:'#f59e0b', info:'#3b82f6' };
  toast.style.cssText =
    'position:fixed;bottom:100px;right:28px;z-index:10001;' +
    'background:' + (colors[type]||colors.info) + ';' +
    'color:#fff;padding:14px 22px;border-radius:12px;font-size:.95rem;' +
    'font-weight:600;max-width:380px;box-shadow:0 6px 30px rgba(0,0,0,.5);' +
    'animation:vcSlideIn .3s ease;';
  toast.textContent = message;

  var style = document.createElement('style');
  style.textContent = '@keyframes vcSlideIn{from{transform:translateX(120%);opacity:0}to{transform:translateX(0);opacity:1}}';
  document.head.appendChild(style);
  document.body.appendChild(toast);
  setTimeout(function(){ toast.remove(); }, duration || 4000);
}

/* ── AUTO-INIT on APEX page load ─────────────────────────── */
document.addEventListener('DOMContentLoaded', function() { vcInit(); });
// Also handle APEX dynamic page loads
if (typeof apex !== 'undefined') {
  apex.jQuery(document).on('apexreadyend', function() { vcInit(); });
}
