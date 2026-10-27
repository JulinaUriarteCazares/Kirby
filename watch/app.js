(function () {
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = window.KIRBY_CONFIG;
  const configured = !SUPABASE_URL.includes('TU-PROYECTO');
  const db = configured ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

  const VIEWS = ['kirby', 'care', 'status', 'events', 'link'];
  const LINK_VIEW = VIEWS.indexOf('link');
  const STORAGE_KEY = 'kirby-watch-pet';
  const TICK_MS = 15000;

  // imágenes según el nivel: [mal, regular, bien]
  const NEEDS = [
    { key: 'hunger', label: 'Comida', pics: ['😫', '🍽️', '😋'], bad: 'Tiene mucha hambre' },
    { key: 'thirst', label: 'Agua', pics: ['🥵', '🥤', '💧'], bad: 'Tiene mucha sed' },
    { key: 'hygiene', label: 'Limpio', pics: ['🪰', '🧼', '✨'], bad: 'Está muy sucio' },
    { key: 'happiness', label: 'Feliz', pics: ['😢', '😐', '😄'], bad: 'Está muy triste' },
    { key: 'energy', label: 'Energía', pics: ['😴', '🥱', '⚡'], bad: 'Está agotado' },
    { key: 'health', label: 'Salud', pics: ['🤒', '🩹', '❤️'], bad: 'Está enfermo' },
  ];

  const $ = (id) => document.getElementById(id);
  const screen = $('screen');
  let pet = null;
  let items = {};
  let events = [];
  let view = 0;
  let open = false;
  let wasAlert = false;
  let channel = null;
  let petId = null;
  try { petId = localStorage.getItem(STORAGE_KEY); } catch (e) { /* sin storage */ }

  // ---------- navegación ----------
  function show(i) {
    view = (i + VIEWS.length) % VIEWS.length;
    document.querySelectorAll('.view').forEach((el) => {
      const idx = VIEWS.indexOf(el.dataset.view);
      el.classList.toggle('active', idx === view);
      el.classList.toggle('left', idx < view);
    });
    $('dots').innerHTML = VIEWS.map((_, j) => `<span class="${j === view ? 'on' : ''}"></span>`).join('');
  }
  $('crown').addEventListener('click', () => show(view + 1));
  $('sideBtn').addEventListener('click', () => show(0));
  $('crown').addEventListener('wheel', (e) => { e.preventDefault(); show(view + (e.deltaY > 0 ? 1 : -1)); }, { passive: false });

  let startX = null;
  screen.addEventListener('pointerdown', (e) => { startX = e.clientX; });
  screen.addEventListener('pointerup', (e) => {
    if (startX == null) return;
    const dx = e.clientX - startX;
    startX = null;
    if (Math.abs(dx) > 45) show(view + (dx < 0 ? 1 : -1));
  });

  // ---------- reloj ----------
  const pad = (n) => String(n).padStart(2, '0');
  function clock() {
    const d = new Date();
    $('clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  setInterval(clock, 1000);
  clock();

  // ---------- sonido "¡Poyo!" sintetizado ----------
  let audio;
  function poyoSound() {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    const t = audio.currentTime;
    const syllable = (start, f1, f2, dur) => {
      const o = audio.createOscillator();
      const g = audio.createGain();
      o.type = 'triangle';
      o.frequency.setValueAtTime(f1, start);
      o.frequency.exponentialRampToValueAtTime(f2, start + dur);
      g.gain.setValueAtTime(0.0001, start);
      g.gain.exponentialRampToValueAtTime(0.45, start + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, start + dur);
      o.connect(g).connect(audio.destination);
      o.start(start);
      o.stop(start + dur + 0.03);
    };
    syllable(t, 650, 1150, 0.12);        // "po"
    syllable(t + 0.15, 1350, 750, 0.22); // "yo"
  }

  // ---------- render ----------
  function needText(p) {
    if (!p.is_alive) return `🪦 ${p.name} ${p.death_cause || 'murió'}`;
    if (p.is_sleeping) return 'Zzz… 💤 (tócalo para despertarlo)';
    const worst = NEEDS.slice().sort((a, b) => p[a.key] - p[b.key])[0];
    if (p[worst.key] < 30) return `${worst.pics[0]} ${worst.bad}`;
    return '¡Poyo! Estoy feliz ⭐';
  }

  function renderKirby() {
    const wrap = $('kirbyBtn');
    let fx = '';
    if (pet && pet.is_sleeping) fx += '<span class="fx zz">💤</span>';
    if (pet && pet.is_alive && pet.hygiene < 25) fx += '<span class="fx fly">🪰</span>';
    wrap.innerHTML = Kirby.svg(pet, { open, items }) + fx;
    $('caption').textContent = pet ? needText(pet) : 'Vincula tu Kirby ➜';
  }

  function ring(n) {
    const v = Math.round(pet[n.key]);
    const level = v < 30 ? 0 : v < 65 ? 1 : 2;
    const color = ['#ff4d5e', '#ffc93c', '#5ccb7a'][level];
    const c = 2 * Math.PI * 23;
    return `<div class="ring ${level === 0 ? 'low' : ''}">
      <svg viewBox="0 0 54 54">
        <circle cx="27" cy="27" r="23" stroke="#2e2440" stroke-width="5" fill="none"/>
        <circle cx="27" cy="27" r="23" stroke="${color}" stroke-width="5" fill="none"
          stroke-linecap="round" stroke-dasharray="${(c * v) / 100} ${c}"/>
      </svg>
      <span class="pic">${pet.is_alive ? n.pics[level] : '💀'}</span>
      <span class="lbl">${n.label} ${v}%</span>
    </div>`;
  }

  function renderStatus() {
    if (!pet) { $('statusTitle').textContent = 'Sin Kirby'; $('rings').innerHTML = ''; return; }
    const bad = NEEDS.filter((n) => pet[n.key] < 30);
    $('statusTitle').textContent = !pet.is_alive ? '💀 Kirby murió'
      : bad.length ? `${bad[0].pics[0]} ${bad[0].bad}` : `😊 ${pet.name} está bien`;
    $('rings').innerHTML = NEEDS.map(ring).join('');
  }

  function renderEvents() {
    $('events').innerHTML = events.length
      ? events.map((e) => {
          const d = new Date(e.created_at);
          return `<li><time>${pad(d.getHours())}:${pad(d.getMinutes())}</time>${e.message || e.type}</li>`;
        }).join('')
      : '<li>Sin actividad todavía</li>';
  }

  function render() {
    screen.classList.toggle('dead', !!pet && !pet.is_alive);
    screen.classList.toggle('sleeping', !!pet && pet.is_alive && pet.is_sleeping);
    const alert = !!pet && pet.is_alive && NEEDS.some((n) => pet[n.key] < 20);
    screen.classList.toggle('alert', alert);
    if (alert && !wasAlert && navigator.vibrate) navigator.vibrate([200, 100, 200]);
    wasAlert = alert;
    renderKirby();
    renderStatus();
    renderEvents();
    const asleep = !!pet && pet.is_sleeping;
    $('sleepBtn').innerHTML = asleep ? '<span>☀️</span>Despertar' : '<span>🌙</span>Dormir';
    document.querySelectorAll('[data-care]').forEach((b) => { b.disabled = !pet || !pet.is_alive; });
  }

  // ---------- reacción de Kirby: se aplasta, abre la boca y suena ----------
  function react(text) {
    const wrap = $('kirbyBtn');
    wrap.classList.remove('squish');
    void wrap.offsetWidth; // reinicia la animación
    wrap.classList.add('squish');
    open = true;
    renderKirby();
    const pop = document.createElement('span');
    pop.className = 'poyo';
    pop.textContent = text;
    wrap.appendChild(pop);
    poyoSound();
    if (navigator.vibrate) navigator.vibrate(40);
    setTimeout(() => { open = false; renderKirby(); }, 650);
  }

  $('kirbyBtn').addEventListener('click', async () => {
    if (!pet) { show(LINK_VIEW); return; }
    if (!pet.is_alive) return;
    react('¡Poyo!');
    const { data, error } = await db.rpc('do_action', { p_id: pet.id, p_action: 'poke' });
    if (!error && data) { pet = data; }
  });

  // ---------- cuidar desde el reloj ----------
  const careMsg = (t) => { $('careMsg').textContent = t; };

  async function careAction(call, reaction, eventMsg) {
    careMsg('…');
    const { data, error } = await call();
    if (error) { careMsg(`❌ ${error.message}`); return; }
    careMsg('');
    pet = data;
    // aviso para el celular (le sale un mensaje y suena el poyo)
    db.from('events').insert({ pet_id: pet.id, type: 'watch', message: eventMsg }).then(() => {});
    render();
    show(0);
    react(reaction);
  }

  function closeFood() {
    $('careGrid').hidden = false;
    $('foodPick').hidden = true;
  }

  async function openFood() {
    $('careGrid').hidden = true;
    $('foodPick').hidden = false;
    $('foodList').innerHTML = '<span class="small">Cargando…</span>';
    const { data } = await db.from('inventory')
      .select('item_id, quantity, shop_items(emoji, name, category)')
      .eq('pet_id', pet.id).gt('quantity', 0);
    const food = (data || []).filter((r) => r.shop_items && ['food', 'drink', 'medicine'].includes(r.shop_items.category));
    $('foodList').innerHTML = food.length
      ? food.map((r) => `<button class="food" data-item="${r.item_id}" title="${r.shop_items.name}">${r.shop_items.emoji}<b>${r.quantity}</b></button>`).join('')
      : '<span class="small">No tiene comida. Cómprala en la app 🛒</span>';
  }

  $('foodBack').addEventListener('click', closeFood);
  $('foodList').addEventListener('click', (e) => {
    const b = e.target.closest('.food');
    if (!b) return;
    const it = items[b.dataset.item] || {};
    closeFood();
    careAction(
      () => db.rpc('use_item', { p_id: pet.id, p_item: b.dataset.item }),
      '¡Ñam!',
      `⌚ Le dieron ${it.emoji || ''} ${it.name || 'comida'} desde el reloj`
    );
  });

  document.querySelectorAll('[data-care]').forEach((btn) => btn.addEventListener('click', () => {
    if (!pet) { show(LINK_VIEW); return; }
    const act = (action, reaction, msg) =>
      careAction(() => db.rpc('do_action', { p_id: pet.id, p_action: action }), reaction, msg);
    switch (btn.dataset.care) {
      case 'feed': openFood(); break;
      case 'water': act('water', '¡Glu glu!', '⌚ Le dieron agua desde el reloj 💧'); break;
      case 'bath': act('bath', '¡Limpio!', '⌚ Lo bañaron desde el reloj 🛁'); break;
      case 'sleep':
        if (pet.is_sleeping) act('wake', '¡Buenos días!', '⌚ Lo despertaron desde el reloj ☀️');
        else act('sleep', 'Zzz…', '⌚ Lo mandaron a dormir desde el reloj 🌙');
        break;
      default:
    }
  }));

  // ---------- datos ----------
  async function loadEvents() {
    const { data } = await db.from('events').select('*').eq('pet_id', petId)
      .order('created_at', { ascending: false }).limit(15);
    events = data || [];
  }

  async function tick() {
    if (!petId) return;
    const { data, error } = await db.rpc('tick_pet', { p_id: petId });
    if (error) {
      if (error.message.includes('no encontrado')) unlink();
      return;
    }
    pet = data;
    render();
  }

  function subscribe() {
    if (channel) db.removeChannel(channel);
    channel = db.channel(`watch-${petId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pets', filter: `id=eq.${petId}` },
        (p) => { pet = p.new; render(); })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'events', filter: `pet_id=eq.${petId}` },
        (p) => {
          events = [p.new, ...events].slice(0, 15);
          if (p.new.type === 'death' && navigator.vibrate) navigator.vibrate([500, 200, 500]);
          renderEvents();
        })
      .subscribe();
  }

  async function connect(id) {
    petId = id;
    try { localStorage.setItem(STORAGE_KEY, id); } catch (e) { /* sin storage */ }
    await Promise.all([tick(), loadEvents()]);
    subscribe();
    render();
  }

  function unlink() {
    petId = null;
    pet = null;
    try { localStorage.removeItem(STORAGE_KEY); } catch (e) { /* sin storage */ }
    render();
    show(LINK_VIEW);
  }

  $('linkBtn').addEventListener('click', async () => {
    const code = $('codeInput').value.trim().toUpperCase();
    if (!configured) { $('linkMsg').textContent = 'Falta configurar config.js'; return; }
    if (code.length < 6) { $('linkMsg').textContent = 'El código tiene 6 letras'; return; }
    $('linkMsg').textContent = 'Buscando…';
    const { data, error } = await db.from('pets').select('id, name').eq('code', code).maybeSingle();
    if (error || !data) { $('linkMsg').textContent = '❌ No encontré ese Kirby'; return; }
    $('linkMsg').textContent = `✅ ¡Conectado con ${data.name}!`;
    await connect(data.id);
    setTimeout(() => show(0), 800);
  });

  // ---------- inicio ----------
  show(0);
  render();
  if (!configured) {
    $('caption').textContent = '⚠️ Configura watch/config.js';
  } else {
    db.from('shop_items').select('id, emoji, name').then(({ data }) => {
      items = Object.fromEntries((data || []).map((i) => [i.id, i]));
      render();
    });
    if (petId) connect(petId); else show(LINK_VIEW);
    setInterval(tick, TICK_MS);
  }
})();
