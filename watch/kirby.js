// Dibujo de Kirby en SVG (mismo diseño que la app móvil)
(function () {
  const INK = '#1B1442';
  const MOUTH = '#8B1A3A';
  const DIRT = [[70, 60, 6], [130, 140, 7], [150, 80, 5], [55, 135, 6], [110, 50, 4], [90, 150, 5], [140, 115, 4], [45, 95, 5], [120, 70, 3]];

  function moodOf(pet) {
    if (!pet) return 'happy';
    if (!pet.is_alive) return 'dead';
    if (pet.is_sleeping) return 'sleep';
    if (pet.health < 35) return 'sick';
    const low = Math.min(pet.hunger, pet.thirst, pet.hygiene, pet.happiness);
    if (low < 20) return 'sad';
    if (low < 45) return 'meh';
    return 'happy';
  }

  function eye(cx, mood) {
    if (mood === 'sleep') return `<path d="M${cx - 10} 88 Q${cx} 97 ${cx + 10} 88" stroke="${INK}" stroke-width="4" fill="none" stroke-linecap="round"/>`;
    if (mood === 'dead') return `<g stroke="${INK}" stroke-width="5" stroke-linecap="round"><line x1="${cx - 9}" y1="76" x2="${cx + 9}" y2="96"/><line x1="${cx + 9}" y1="76" x2="${cx - 9}" y2="96"/></g>`;
    const ry = mood === 'sick' ? 14 : 20;
    return `<ellipse cx="${cx}" cy="86" rx="8.5" ry="${ry}" fill="${INK}"/>
      <ellipse cx="${cx}" cy="${86 + ry * 0.45}" rx="6" ry="${ry * 0.4}" fill="#3B6FE0"/>
      <ellipse cx="${cx}" cy="${86 - ry * 0.5}" rx="5" ry="${ry * 0.38}" fill="#fff"/>`;
  }

  // ojeras (energía < 35) y párpados caídos (energía < 15)
  function tired(cx, energy, body) {
    let s = `<path d="M${cx - 11} 109 Q${cx} 117 ${cx + 11} 109" stroke="#7B4FA0" stroke-width="3.5" fill="none" stroke-linecap="round" opacity="0.75"/>
      <path d="M${cx - 8} 114 Q${cx} 120 ${cx + 8} 114" stroke="#7B4FA0" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.45"/>`;
    if (energy < 15) s += `<path d="M${cx - 12} 64 L${cx + 12} 64 L${cx + 12} 84 Q${cx} 79 ${cx - 12} 84 Z" fill="${body}" stroke="#E2799A" stroke-width="1.5"/>`;
    return s;
  }

  function mouth(mood, open) {
    if (open) return `<ellipse cx="100" cy="123" rx="15" ry="17" fill="${MOUTH}"/><ellipse cx="100" cy="133" rx="10" ry="6" fill="#FF6B8B"/>`;
    switch (mood) {
      case 'happy': return `<path d="M88 115 Q100 133 112 115 Q100 122 88 115 Z" fill="${MOUTH}"/>`;
      case 'meh': return `<path d="M92 121 Q100 125 108 121" stroke="${MOUTH}" stroke-width="4" fill="none" stroke-linecap="round"/>`;
      case 'sleep': return `<ellipse cx="100" cy="122" rx="4" ry="5" fill="${MOUTH}"/>`;
      case 'dead': return `<path d="M86 124 q4 -6 7 0 t7 0 t7 0 t7 0" stroke="${MOUTH}" stroke-width="3.5" fill="none" stroke-linecap="round"/>`;
      default: return `<path d="M89 127 Q100 115 111 127" stroke="${MOUTH}" stroke-width="4" fill="none" stroke-linecap="round"/>`;
    }
  }

  /** items: { id: {emoji} } para dibujar la ropa */
  function kirbySvg(pet, { open = false, items = {} } = {}) {
    const mood = moodOf(pet);
    const dead = mood === 'dead';
    const hygiene = pet ? pet.hygiene : 100;
    const energy = pet ? pet.energy : 100;
    const isTired = energy < 35 && mood !== 'sleep' && mood !== 'dead';
    const dirt = hygiene < 15 ? 9 : hygiene < 35 ? 6 : hygiene < 60 ? 3 : 0;
    const body = dead ? '#E8DCE6' : mood === 'sick' ? '#EBC0CF' : '#FFAFC5';
    const outfit = (pet && pet.outfit) || {};
    const wear = (slot, y, size) => {
      const it = outfit[slot] && items[outfit[slot]];
      return it ? `<text x="100" y="${y}" font-size="${size}" text-anchor="middle">${it.emoji}</text>` : '';
    };
    const wave = mood === 'happy';

    return `<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <g class="body" ${dead ? 'opacity="0.65"' : ''}>
        ${dead ? '<ellipse cx="100" cy="22" rx="40" ry="9" stroke="#FFD84D" stroke-width="6" fill="none"/>' : ''}
        ${dead ? '' : '<ellipse cx="62" cy="172" rx="32" ry="17" fill="#E5304B"/><ellipse cx="138" cy="172" rx="32" ry="17" fill="#E5304B"/>'}
        <ellipse cx="33" cy="112" rx="20" ry="15" fill="${body}" stroke="#E2799A" stroke-width="2"/>
        <ellipse cx="167" cy="${wave ? 92 : 112}" rx="20" ry="15" fill="${body}" stroke="#E2799A" stroke-width="2" ${wave ? 'transform="rotate(-35 167 100)"' : ''}/>
        <circle cx="100" cy="102" r="72" fill="${body}" stroke="#E2799A" stroke-width="2.5"/>
        ${DIRT.slice(0, dirt).map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#7A5230" opacity="0.5"/>`).join('')}
        ${eye(82, mood)}${eye(118, mood)}
        ${isTired ? tired(82, energy, body) + tired(118, energy, body) : ''}
        ${mood === 'sad' ? '<ellipse cx="72" cy="112" rx="4" ry="7" fill="#5BC0FF"/>' : ''}
        <ellipse cx="60" cy="114" rx="13" ry="7" fill="#FF5C8A" opacity="0.55"/>
        <ellipse cx="140" cy="114" rx="13" ry="7" fill="#FF5C8A" opacity="0.55"/>
        ${mouth(mood, open && !dead)}
        ${wear('hat', 42, 70)}${wear('face', 108, 58)}${wear('neck', 165, 42)}
      </g>
    </svg>`;
  }

  window.Kirby = { svg: kirbySvg, moodOf };
})();
