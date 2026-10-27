-- =====================================================================
--  ACTUALIZACIÓN 2: Pluma de Fénix 🪶 (revivir a Kirby)
--  Pega esto en Supabase > SQL Editor > Run.  NO borra tus datos.
-- =====================================================================

insert into public.shop_items (id, name, category, emoji, price, slot, hunger, thirst, hygiene, happiness, energy, health, description, sort)
values ('phoenix', 'Pluma de Fénix', 'medicine', '🪶', 400, null, 0, 0, 0, 0, 0, 0, 'Revive a Kirby si muere', 33)
on conflict (id) do update set name = excluded.name, price = excluded.price, emoji = excluded.emoji, description = excluded.description;

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

grant execute on all functions in schema public to anon, authenticated;
