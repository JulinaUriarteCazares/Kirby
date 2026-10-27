# Kirby Pou ⭐

- `supabase/schema.sql`: base de datos con toda la lógica (paso del tiempo, muerte, tienda, armas)
- `mobile/`: app para celular (Expo Go)
- `watch/`: app del smartwatch (web, simula un reloj redondo)

## 1. Base de datos
Supabase → **SQL Editor** → New query → pega todo `supabase/schema.sql` → **Run**.
(Se puede volver a correr, pero borra los datos y empieza de cero.)

## 2. Llaves
En Supabase → Project Settings → API copia la **Project URL** y la llave **anon / publishable** y pégalas en:
- `mobile/src/config.js`
- `watch/config.js`

## 3. Celular
```bash
cd mobile
npm install
npx expo start
```
Escanea el QR con **Expo Go**. Adopta un Kirby. En ⚙️ verás el **código** para el reloj.

## 4. Smartwatch
Sirve la carpeta `watch` con cualquier servidor estático, por ejemplo:
```bash
cd watch
npx serve .
```
Abre la URL, ve a la pantalla de vincular y escribe el código.
- Toca a Kirby: abre la boca, dice "¡Poyo!" y en el celular aparece el aviso.
- Gira la corona o desliza para ver el estado (hambre, sed, limpieza, tristeza…) y la actividad.

## Cómo funciona
- Cada ~15–20 s los clientes llaman `tick_pet`, que baja las barras según el tiempo que pasó (aunque la app esté cerrada).
- Si pasa mucho tiempo con comida, agua, limpieza o felicidad en 0, pierde salud y **muere**. También muere si usas el 🔪 o la 🔫 desde la Mochila.
- Al morir puedes reencarnarlo; conserva monedas, ropa y decoración.
