-- =====================================================================
--  KIRBY POU  ·  Esquema completo para Supabase
--  Pega TODO este archivo en Supabase > SQL Editor > New query > Run
--  (se puede volver a correr: borra y recrea todo)
-- =====================================================================

-- ---------- Limpieza (para poder re-ejecutar) ----------
-- (borrar la tabla pets con cascade también borra las funciones que la usan)
drop table if exists public.deaths cascade;
drop table if exists public.game_scores cascade;
drop table if exists public.events cascade;
drop table if exists public.inventory cascade;
drop table if exists public.pets cascade;
drop table if exists public.shop_items cascade;
drop function if exists public.create_pet(text) cascade;
drop function if exists public.clamp100(double precision) cascade;

create extension if not exists pgcrypto;

-- ---------- Tablas ----------

-- Catálogo de la tienda
create table public.shop_items (
  id          text primary key,
  name        text not null,
  category    text not null check (category in
                ('food','drink','medicine','toy','clothes','decor','weapon')),
  emoji       text not null,
  price       int  not null check (price >= 0),
  slot        text,                -- ropa: hat | face | neck
  hunger      real not null default 0,
  thirst      real not null default 0,
  hygiene     real not null default 0,
  happiness   real not null default 0,
  energy      real not null default 0,
  health      real not null default 0,
  description text,
  sort        int  not null default 0
);

-- La mascota (1 Kirby por jugador). "code" sirve para vincular el reloj.
create table public.pets (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique default upper(substr(md5(random()::text), 1, 6)),
  name         text not null default 'Kirby',
  hunger       double precision not null default 80,   -- 100 = lleno, 0 = muriendo de hambre
  thirst       double precision not null default 80,   -- 100 = hidratado
  hygiene      double precision not null default 80,   -- 100 = limpio
  happiness    double precision not null default 80,
  energy       double precision not null default 80,
  health       double precision not null default 100,
  coins        int  not null default 150,
  xp           int  not null default 0,
  is_alive     boolean not null default true,
  is_sleeping  boolean not null default false,
  death_cause  text,
  died_at      timestamptz,
  outfit       jsonb not null default '{}'::jsonb,  -- {"hat":"crown","face":"sunglasses"}
  room         jsonb not null default '[]'::jsonb,  -- [{"item":"plant","x":0.2,"y":0.7}]
  born_at      timestamptz not null default now(),
  last_tick    timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

create table public.inventory (
  pet_id   uuid not null references public.pets(id) on delete cascade,
  item_id  text not null references public.shop_items(id) on delete cascade,
  quantity int  not null default 0 check (quantity >= 0),
  primary key (pet_id, item_id)
);

-- Historial de cosas que pasan (lo usa el reloj y el móvil para avisos)
create table public.events (
  id         bigserial primary key,
  pet_id     uuid not null references public.pets(id) on delete cascade,
  type       text not null,
  message    text,
  created_at timestamptz not null default now()
);
create index events_pet_idx on public.events (pet_id, created_at desc);

create table public.game_scores (
  id         bigserial primary key,
  pet_id     uuid not null references public.pets(id) on delete cascade,
  game       text not null,
  score      int  not null,
  coins      int  not null,
  created_at timestamptz not null default now()
);

-- Cementerio
create table public.deaths (
  id         bigserial primary key,
  pet_id     uuid references public.pets(id) on delete set null,
  pet_name   text not null,
  cause      text not null,
  age_hours  double precision not null,
  died_at    timestamptz not null default now()
);

-- ---------- Helpers ----------
create or replace function public.clamp100(v double precision)
returns double precision language sql immutable as $$
  select greatest(0, least(100, v));
$$;

-- Mata al Kirby (uso interno). Devuelve la fila actualizada.
create or replace function public.kill_pet_internal(p public.pets, p_cause text)
returns public.pets language plpgsql as $$
declare r public.pets;
begin
  update public.pets
     set is_alive = false, is_sleeping = false, health = 0,
         death_cause = p_cause, died_at = now(), last_tick = now()
   where id = p.id
  returning * into r;

  insert into public.deaths (pet_id, pet_name, cause, age_hours)
  values (p.id, p.name, p_cause, extract(epoch from (now() - p.born_at)) / 3600.0);

  insert into public.events (pet_id, type, message)
  values (p.id, 'death', p.name || ' murió: ' || p_cause);
  return r;
end $$;

-- ---------- Paso del tiempo ----------
-- Aplica el desgaste desde la última vez. Ambos clientes lo llaman seguido.
-- Si el Kirby pasa mucho tiempo con hambre/sed en 0 pierde salud y muere.
create or replace function public.tick_pet(p_id uuid)
returns public.pets language plpgsql as $$
declare
  p  public.pets;
  h  double precision;
  -- velocidades por hora
  r_hun double precision; r_thi double precision; r_hyg double precision;
  r_hap double precision; r_ene double precision;
  dmg double precision := 0;
  cause text;
begin
  select * into p from public.pets where id = p_id for update;
  if not found then raise exception 'Kirby no encontrado'; end if;
  if not p.is_alive then return p; end if;

  h := extract(epoch from (now() - p.last_tick)) / 3600.0;
  if h <= 0 then return p; end if;

  if p.is_sleeping then
    r_hun := 4; r_thi := 5; r_hyg := 2; r_hap := 0; r_ene := -30;  -- negativo = sube
  else
    r_hun := 10; r_thi := 14; r_hyg := 6; r_hap := 7; r_ene := 6;
  end if;

  -- daño solo por el tiempo que el stat estuvo en 0
  dmg := dmg + 15 * greatest(0, h - p.hunger    / r_hun);
  dmg := dmg + 20 * greatest(0, h - p.thirst    / r_thi);
  dmg := dmg +  5 * greatest(0, h - p.hygiene   / r_hyg);
  if r_hap > 0 then dmg := dmg + 5 * greatest(0, h - p.happiness / r_hap); end if;

  p.hunger    := clamp100(p.hunger    - r_hun * h);
  p.thirst    := clamp100(p.thirst    - r_thi * h);
  p.hygiene   := clamp100(p.hygiene   - r_hyg * h);
  p.happiness := clamp100(p.happiness - r_hap * h);
  p.energy    := clamp100(p.energy    - r_ene * h);

  if p.is_sleeping and p.energy >= 100 then p.is_sleeping := false; end if;

  if dmg > 0 then
    p.health := clamp100(p.health - dmg);
  elsif p.hunger > 50 and p.thirst > 50 and p.hygiene > 30 then
    p.health := clamp100(p.health + 4 * h);   -- se recupera si está bien cuidado
  end if;

  update public.pets
     set hunger = p.hunger, thirst = p.thirst, hygiene = p.hygiene,
         happiness = p.happiness, energy = p.energy, health = p.health,
         is_sleeping = p.is_sleeping, last_tick = now()
   where id = p.id
  returning * into p;

  if p.health <= 0 then
    cause := case
      when p.thirst  <= 0 then 'se murió de sed'
      when p.hunger  <= 0 then 'se murió de hambre'
      when p.hygiene <= 0 then 'se murió de una infección por suciedad'
      else 'se murió de tristeza' end;
    p := public.kill_pet_internal(p, cause);
  end if;
  return p;
end $$;

-- ---------- Acciones gratis ----------
-- bath | water | pet | poke (desde el reloj) | sleep | wake
create or replace function public.do_action(p_id uuid, p_action text)
returns public.pets language plpgsql as $$
declare p public.pets; msg text;
begin
  p := public.tick_pet(p_id);
  if not p.is_alive then raise exception 'Kirby está muerto 💀'; end if;
  if p.is_sleeping and p_action not in ('wake','poke') then
    raise exception 'Shhh… Kirby está dormido 😴';
  end if;

  case p_action
    when 'bath'  then p.hygiene := 100; p.happiness := clamp100(p.happiness + 5); msg := '¡Kirby se bañó! 🛁';
    when 'water' then p.thirst  := clamp100(p.thirst + 20);  msg := 'Kirby tomó agua del grifo 💧';
    when 'pet'   then p.happiness := clamp100(p.happiness + 3);
    when 'poke'  then
      p.happiness := clamp100(p.happiness + 2);
      if p.is_sleeping then p.is_sleeping := false; msg := '⌚ ¡Despertaron a Kirby desde el reloj!';
      else msg := '⌚ ¡Poyo! Aplastaron a Kirby desde el reloj'; end if;
    when 'sleep' then p.is_sleeping := true;  msg := 'Kirby se fue a dormir 😴';
    when 'wake'  then p.is_sleeping := false; msg := 'Kirby despertó ☀️';
    else raise exception 'Acción desconocida: %', p_action;
  end case;

  update public.pets
     set hygiene = p.hygiene, thirst = p.thirst, happiness = p.happiness,
         is_sleeping = p.is_sleeping, xp = xp + 1
   where id = p.id
  returning * into p;

  if msg is not null then
    insert into public.events (pet_id, type, message) values (p.id, p_action, msg);
  end if;
  return p;
end $$;

-- ---------- Tienda ----------
create or replace function public.buy_item(p_id uuid, p_item text)
returns public.pets language plpgsql as $$
declare p public.pets; it public.shop_items; owned int;
begin
  p := public.tick_pet(p_id);
  if not p.is_alive and p_item <> 'phoenix' then raise exception 'Kirby está muerto 💀'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception 'Ese producto no existe'; end if;

  select quantity into owned from public.inventory where pet_id = p_id and item_id = p_item;
  if it.category in ('clothes','decor','toy','weapon') and coalesce(owned, 0) > 0 then
    raise exception 'Ya tienes %', it.name;
  end if;
  if p.coins < it.price then raise exception 'No te alcanzan las monedas 🪙'; end if;

  update public.pets set coins = coins - it.price where id = p_id returning * into p;
  insert into public.inventory (pet_id, item_id, quantity) values (p_id, p_item, 1)
  on conflict (pet_id, item_id) do update set quantity = public.inventory.quantity + 1;

  insert into public.events (pet_id, type, message)
  values (p_id, 'buy', 'Compraste ' || it.emoji || ' ' || it.name);
  return p;
end $$;

-- Usar algo del inventario: comer, beber, curar, jugar, ponerse ropa o… usar un arma.
create or replace function public.use_item(p_id uuid, p_item text)
returns public.pets language plpgsql as $$
declare p public.pets; it public.shop_items; owned int; slot_now text;
begin
  if p_item = 'phoenix' then return public.revive_with_item(p_id); end if;
  p := public.tick_pet(p_id);
  if not p.is_alive then raise exception 'Kirby está muerto 💀'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception 'Ese producto no existe'; end if;
  select quantity into owned from public.inventory where pet_id = p_id and item_id = p_item;
  if coalesce(owned, 0) <= 0 then raise exception 'No tienes %', it.name; end if;

  if it.category = 'weapon' then
    return public.kill_pet_internal(p,
      case p_item when 'knife' then 'fue apuñalado con un cuchillo 🔪'
                  when 'gun'   then 'recibió un disparo 🔫'
                  else 'fue asesinado con ' || it.name end);
  end if;

  if it.category = 'clothes' then
    slot_now := p.outfit ->> it.slot;
    update public.pets
       set outfit = case when slot_now = p_item then outfit - it.slot
                         else jsonb_set(outfit, array[it.slot], to_jsonb(p_item)) end
     where id = p_id returning * into p;
    return p;
  end if;

  if it.category = 'decor' then
    raise exception 'La decoración se coloca desde la sala';
  end if;

  if p.is_sleeping then raise exception 'Shhh… Kirby está dormido 😴'; end if;
  if it.category = 'toy' and p.energy < 5 then raise exception 'Kirby está muy cansado para jugar'; end if;

  update public.pets
     set hunger    = clamp100(hunger    + it.hunger),
         thirst    = clamp100(thirst    + it.thirst),
         hygiene   = clamp100(hygiene   + it.hygiene),
         happiness = clamp100(happiness + it.happiness),
         energy    = clamp100(energy    + it.energy),
         health    = clamp100(health    + it.health),
         xp        = xp + 2
   where id = p_id returning * into p;

  -- comida, bebida y medicina se gastan; los juguetes se quedan
  if it.category in ('food','drink','medicine') then
    update public.inventory set quantity = quantity - 1 where pet_id = p_id and item_id = p_item;
  end if;

  insert into public.events (pet_id, type, message)
  values (p_id, 'use', 'Kirby usó ' || it.emoji || ' ' || it.name);
  return p;
end $$;

-- ---------- Minijuegos ----------
create or replace function public.award_coins(p_id uuid, p_game text, p_score int, p_coins int)
returns public.pets language plpgsql as $$
declare p public.pets; c int := greatest(0, least(coalesce(p_coins, 0), 300));
begin
  p := public.tick_pet(p_id);
  if not p.is_alive then raise exception 'Kirby está muerto 💀'; end if;
  update public.pets
     set coins = coins + c,
         happiness = clamp100(happiness + 12),
         energy    = clamp100(energy - 8),
         xp        = xp + 5
   where id = p_id returning * into p;
  insert into public.game_scores (pet_id, game, score, coins) values (p_id, p_game, p_score, c);
  insert into public.events (pet_id, type, message)
  values (p_id, 'game', 'Kirby jugó ' || p_game || ' y ganó ' || c || ' 🪙');
  return p;
end $$;

-- ---------- Crear / reencarnar ----------
create or replace function public.create_pet(p_name text)
returns public.pets language plpgsql as $$
declare p public.pets;
begin
  insert into public.pets (name) values (coalesce(nullif(trim(p_name), ''), 'Kirby'))
  returning * into p;
  insert into public.inventory (pet_id, item_id, quantity) values
    (p.id, 'apple', 3), (p.id, 'water_bottle', 2), (p.id, 'cookie', 2), (p.id, 'ball', 1);
  insert into public.events (pet_id, type, message) values (p.id, 'born', '¡Nació ' || p.name || '! ⭐');
  return p;
end $$;

-- Revivir con la Pluma de Fénix: vuelve con todo al 100 y conserva su edad y monedas
create or replace function public.revive_with_item(p_id uuid)
returns public.pets language plpgsql as $$
declare p public.pets; owned int;
begin
  select * into p from public.pets where id = p_id for update;
  if not found then raise exception 'Kirby no encontrado'; end if;
  if p.is_alive then raise exception 'Kirby está vivo. Guarda la pluma para cuando muera 🪶'; end if;
  select quantity into owned from public.inventory where pet_id = p_id and item_id = 'phoenix';
  if coalesce(owned, 0) <= 0 then raise exception 'No tienes Pluma de Fénix 🪶'; end if;

  update public.inventory set quantity = quantity - 1 where pet_id = p_id and item_id = 'phoenix';
  update public.pets
     set hunger = 100, thirst = 100, hygiene = 100, happiness = 100, energy = 100, health = 100,
         is_alive = true, is_sleeping = false, death_cause = null, died_at = null, last_tick = now()
   where id = p_id returning * into p;
  insert into public.events (pet_id, type, message)
  values (p_id, 'revive', '🪶 ¡' || p.name || ' revivió con la Pluma de Fénix!');
  return p;
end $$;

-- Reencarnar gratis: empieza de cero y pierde la mitad de las monedas
create or replace function public.revive_pet(p_id uuid)
returns public.pets language plpgsql as $$
declare p public.pets;
begin
  update public.pets
     set hunger = 80, thirst = 80, hygiene = 80, happiness = 80, energy = 80, health = 100, coins = coins / 2,
         is_alive = true, is_sleeping = false, death_cause = null, died_at = null,
         born_at = now(), last_tick = now()
   where id = p_id returning * into p;
  if not found then raise exception 'Kirby no encontrado'; end if;
  insert into public.events (pet_id, type, message) values (p.id, 'born', '¡' || p.name || ' reencarnó! ⭐');
  return p;
end $$;

-- ---------- Catálogo ----------
insert into public.shop_items (id, name, category, emoji, price, slot, hunger, thirst, hygiene, happiness, energy, health, description, sort) values
-- comida
('apple',        'Manzana',          'food', '🍎', 10,  null, 15, 2,  0,  2,  0,  1, 'Sana y crujiente', 1),
('cookie',       'Galleta',          'food', '🍪', 8,   null, 10, -3, 0,  5,  0,  0, 'Un antojito', 2),
('watermelon',   'Sandía',           'food', '🍉', 20,  null, 15, 20, 0,  4,  0,  2, 'Come y se hidrata', 3),
('burger',       'Hamburguesa',      'food', '🍔', 25,  null, 35, -5, -3, 6,  3,  0, 'Muy llenadora', 4),
('pizza',        'Pizza',            'food', '🍕', 30,  null, 40, -5, -3, 8,  3,  0, '¡Poyo!', 5),
('ramen',        'Ramen',            'food', '🍜', 30,  null, 35, 10, 0,  6,  4,  1, 'Calientito', 6),
('sushi',        'Sushi',            'food', '🍣', 35,  null, 30, 0,  0,  6,  0,  3, 'Fresco', 7),
('icecream',     'Helado',           'food', '🍦', 15,  null, 10, 5,  0,  10, 0,  0, 'Para días felices', 8),
('cake',         'Pastel',           'food', '🍰', 40,  null, 25, -3, -2, 18, 5,  0, 'Su favorito', 9),
('maxim_tomato', 'Tomate Máximo',    'food', '🍅', 90,  null, 50, 10, 0,  15, 20, 40, 'Recupera mucha salud', 10),
-- bebidas
('water_bottle', 'Botella de agua',  'drink', '💧', 5,  null, 0, 30, 0,  1,  0,  1, 'Básica', 20),
('milk',         'Leche',            'drink', '🥛', 10, null, 3, 30, 0,  2,  0,  2, 'Huesos fuertes', 21),
('juice',        'Jugo',             'drink', '🧃', 12, null, 2, 35, 0,  4,  2,  0, 'De cajita', 22),
('soda',         'Refresco',         'drink', '🥤', 15, null, 0, 40, 0,  6,  8,  -1, 'Burbujas', 23),
('coffee',       'Café',             'drink', '☕', 18, null, 0, 20, 0,  2,  35, 0, 'Quita el sueño', 24),
('boba',         'Té de burbujas',   'drink', '🧋', 22, null, 8, 40, 0,  10, 3,  0, 'Con perlitas', 25),
-- medicina
('bandage',      'Curita',           'medicine', '🩹', 30,  null, 0, 0, 0, 2, 0, 15,  'Para raspones', 30),
('pill',         'Medicina',         'medicine', '💊', 60,  null, 0, 0, 0, -3, 0, 40, 'Sabe feo pero cura', 31),
('potion',       'Poción de vida',   'medicine', '🧪', 150, null, 20, 20, 20, 20, 20, 100, 'Lo deja como nuevo', 32),
('phoenix',      'Pluma de Fénix',   'medicine', '🪶', 400, null, 0, 0, 0, 0, 0, 0, 'Revive a Kirby si muere', 33),
-- juguetes (no se gastan)
('ball',         'Pelota',           'toy', '⚽', 40,  null, -3, -5, -5, 15, -8, 0, 'A patear', 40),
('yoyo',         'Yoyo',             'toy', '🪀', 30,  null, -1, -2, 0,  10, -4, 0, 'Arriba y abajo', 41),
('kite',         'Papalote',         'toy', '🪁', 60,  null, -3, -5, -2, 18, -8, 0, 'Vuela alto', 42),
('videogame',    'Videojuego',       'toy', '🎮', 150, null, -2, -3, 0,  25, -5, 0, 'Horas de diversión', 43),
('teddy',        'Peluche',          'toy', '🧸', 70,  null, 0,  0,  0,  15, 3,  0, 'Para abrazar', 44),
-- ropa
('bow',          'Moño',             'clothes', '🎀', 60,  'hat',  0,0,0,0,0,0, 'Coqueto', 50),
('cap',          'Gorra',            'clothes', '🧢', 80,  'hat',  0,0,0,0,0,0, 'Deportiva', 51),
('grad_cap',     'Birrete',          'clothes', '🎓', 120, 'hat',  0,0,0,0,0,0, 'Kirby graduado', 52),
('tophat',       'Sombrero de copa', 'clothes', '🎩', 150, 'hat',  0,0,0,0,0,0, 'Muy elegante', 53),
('crown',        'Corona',           'clothes', '👑', 300, 'hat',  0,0,0,0,0,0, 'Rey de Dream Land', 54),
('glasses',      'Lentes',           'clothes', '👓', 70,  'face', 0,0,0,0,0,0, 'Intelectual', 55),
('sunglasses',   'Lentes de sol',    'clothes', '🕶️', 120, 'face', 0,0,0,0,0,0, 'Cool', 56),
('goggles',      'Goggles',          'clothes', '🥽', 90,  'face', 0,0,0,0,0,0, 'Para nadar', 57),
('scarf',        'Bufanda',          'clothes', '🧣', 110, 'neck', 0,0,0,0,0,0, 'Calientita', 58),
('necklace',     'Collar',           'clothes', '📿', 90,  'neck', 0,0,0,0,0,0, 'Brillante', 59),
('medal',        'Medalla',          'clothes', '🏅', 200, 'neck', 0,0,0,0,0,0, 'Campeón', 60),
-- decoración (se coloca en la sala)
('plant',        'Planta',           'decor', '🪴', 50,  null, 0,0,0,0,0,0, 'Verde', 70),
('star_deco',    'Estrella',         'decor', '🌟', 40,  null, 0,0,0,0,0,0, 'Warp Star', 71),
('picture',      'Cuadro',           'decor', '🖼️', 80,  null, 0,0,0,0,0,0, 'Arte', 72),
('fishbowl',     'Pecera',           'decor', '🐠', 90,  null, 0,0,0,0,0,0, 'Glu glu', 73),
('tree',         'Arbolito',         'decor', '🎄', 100, null, 0,0,0,0,0,0, 'Navideño', 74),
('disco',        'Bola disco',       'decor', '🪩', 120, null, 0,0,0,0,0,0, 'Fiesta', 75),
('sofa',         'Sillón',           'decor', '🛋️', 150, null, 0,0,0,0,0,0, 'Cómodo', 76),
('tv',           'Tele',             'decor', '📺', 180, null, 0,0,0,0,0,0, 'Caricaturas', 77),
('bed',          'Cama',             'decor', '🛏️', 200, null, 0,0,0,0,0,0, 'Mullida', 78),
-- armas
('knife',        'Cuchillo',         'weapon', '🔪', 300, null, 0,0,0,0,0,0, 'Peligroso… mata a Kirby', 90),
('gun',          'Pistola',          'weapon', '🔫', 600, null, 0,0,0,0,0,0, 'Muy peligroso… mata a Kirby', 91);

-- ---------- Seguridad / acceso ----------
-- App sin login: se permite todo a la llave anon. (Es un juego; no guardes datos sensibles.)
alter table public.shop_items  enable row level security;
alter table public.pets        enable row level security;
alter table public.inventory   enable row level security;
alter table public.events      enable row level security;
alter table public.game_scores enable row level security;
alter table public.deaths      enable row level security;

create policy "shop read"   on public.shop_items  for select using (true);
create policy "pets all"    on public.pets        for all using (true) with check (true);
create policy "inv all"     on public.inventory   for all using (true) with check (true);
create policy "events all"  on public.events      for all using (true) with check (true);
create policy "scores all"  on public.game_scores for all using (true) with check (true);
create policy "deaths all"  on public.deaths      for all using (true) with check (true);

grant usage on schema public to anon, authenticated;
grant select on public.shop_items to anon, authenticated;
grant select, insert, update, delete on public.pets, public.inventory, public.events,
      public.game_scores, public.deaths to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;

-- ---------- Realtime (el reloj y el móvil se actualizan al instante) ----------
do $$
begin
  begin alter publication supabase_realtime add table public.pets;   exception when others then null; end;
  begin alter publication supabase_realtime add table public.events; exception when others then null; end;
end $$;
