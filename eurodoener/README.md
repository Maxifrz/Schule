# Euro Döner Clausthal-Zellerfeld — Website

Standalone Landing-Page für den Döner- & Pizza-Imbiss Euro Döner in
Clausthal-Zellerfeld.

## Struktur

- `index.html` — komplett eigenständig, keine externen Assets, keine
  Font-CDNs, keine JS-Frameworks

## Designsystem

Umgesetzt nach dem vorgegebenen Euro-Döner-Designsystem (modern-gemütlicher
Diner-Charakter, Street-Food-cool):

- **Farben**: Döner-Rot `#D42027` (CTAs/Preise, sparsam eingesetzt),
  Grill-Orange (Icons/„Beliebt"), Backstein-Braun (Über-uns), Kraftpapier-Ton
  (Speisekarte), Creme-Weiß-Hintergrund, Salat-Grün (Veggie-Tags),
  Sonnen-Gelb (Bewertungssterne)
- **Typografie**: kondensierte Versal-Display-Schrift für Headlines/Logo,
  freundliche System-Sans für Fließtext
- **Neon-Hero** mit rot glühender „EURO DÖNER"-Leuchtschrift (dezentes
  Flackern), warme Grill-Glut-Partikel auf Canvas, Schachbrett-Streifen
- **Bestell-Modi** (Vor Ort · Mitnehmen · Lieferung) als Kernvorteil
  prominent im Hero und als eigene Karten-Sektion
- **Lockere Du-Tonalität** („Hunger? Wir liefern.", „Frisch vom Spieß.")

## Features

- Die drei Kernfragen (Was? Wann? Wo?) direkt above the fold:
  dynamischer Öffnungsstatus („Jetzt geöffnet — bis 23:00 Uhr"),
  klickbare Adresse und Telefonnummer
- Zwei CTAs im Hero (primär „Jetzt bestellen"), „Bestellen"-Button dauerhaft
  in der Navigation, Sticky-Bestell-Bar auf Mobilgeräten
- Tabbed Speisekarte (Döner & Dürüm, Pizza, Calzone & Ofen, Snacks, Getränke)
  mit Preisen, „Beliebt"-Badges, Vegetarisch-/Vegan-Tags und
  Allergenkennzeichnung nach LMIV inkl. Legende
- Öffnungszeiten mit automatischer Hervorhebung des heutigen Tags
- Dark-/Light-Mode über `prefers-color-scheme`
- JSON-LD Restaurant-Schema (servesCuisine, priceRange, Öffnungszeiten)
- Barrierefrei: Skip-Link, Tastatur-Tabs, ARIA, sichtbare Fokus-Ringe,
  WCAG-AA-Kontraste, `prefers-reduced-motion`, 4,5★-Anzeige exakt
  (nicht als volle 5 Sterne dargestellt)

## Qualitätssicherung

Die Seite wurde nach einer sechsdimensionalen adversarialen Review
(Korrektheit, Barrierefreiheit, Design-Treue, Mobile, SEO/Recht, Copy)
überarbeitet. Behobene Punkte u. a.: Kontrast von Beschreibungen/Badges/
Eyebrow-Labels auf WCAG AA angehoben, mobile Navigation ab 860 px (kein
Overflow im Tablet-Bereich mehr), zugänglicher Name für den Bestell-Button,
Canvas-Animation pausiert korrekt außerhalb des Viewports.

## Vor dem Livegang (vom Betreiber zu erledigen)

- Impressum und Datenschutzerklärung im Footer vervollständigen
  (Platzhalter sind mit „[Vom Betreiber zu ergänzen: …]" markiert)
- Echte Produktfotos (Döner im Kraftpapier, Pizza, Calzone) ergänzen —
  „Menschen bestellen mit den Augen"
- Speisekarte, Preise und Allergenkennzeichnung mit der Küche abgleichen
- Liefergebiet, Mindestbestellwert und ggf. Bestellportale eintragen
- Google Business Profile mit denselben NAP-Daten verknüpfen

## Deployment

`index.html` auf einen beliebigen Webserver / CDN laden — keine Buildschritte,
keine Abhängigkeiten.

## Kontakt Restaurant

- **Adresse:** Adolph-Roemer-Straße 7, 38678 Clausthal-Zellerfeld
- **Telefon:** +49 5323 840230
- **Öffnungszeiten:** täglich 11:00–23:00 Uhr
- **Angebot:** Döner, Pizza, Pizzeria · Vor Ort · Mitnehmen · Lieferung
