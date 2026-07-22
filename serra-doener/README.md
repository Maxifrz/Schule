# Serra Döner Clausthal-Zellerfeld — Website

Standalone Landing-Page mit Online-Bestellstrecke für den Serra Imbiss,
„den ersten Online-Döner der Welt", seit 2005 in Clausthal-Zellerfeld.

## Struktur

- `index.html` — komplett eigenständig, keine externen Assets, keine
  Font-CDNs, keine JS-Frameworks

## Designsystem

Umgesetzt nach dem vorgegebenen Serra-Designsystem — die Rot/Gelb-Identität
harmonisiert und digital-tauglich gemacht:

- **Farben**: Serra-Rot `#E2231A` (Header, CTAs), Rot-Dunkel `#B01810`
  (Hover, Preistext), Serra-Gelb `#FFC20E` als *gezielter* Akzent (nicht
  mehr als riesige Vollfläche), Anthrazit-Grill `#1F1D1B` für dunkle
  Sektionen, Off-White `#FBFAF7` als Hintergrund, Sesam-Beige `#EBDCC0`
  für sanfte Flächen, Salat-Grün für Frische-Tags
- **Typografie**: kondensierte Display-Schrift für Headlines/Wortmarke,
  klare System-Sans für Fließtext und Bestellstrecke — Schluss mit der
  schwer lesbaren Deko-Schrift
- **Heritage bewusst inszeniert**: „seit 2005", ®-Wortmarke, rotierender
  „SEIT 2005"-Stempel, die persönliche Note des Inhabers Zekai Ayvaz
  („Es war uns eine Ehre, Sie zu bedienen.")
- **Warme, ruhige Anmutung** — bewusst anders als ein lautes Neon-Konzept

## Kernfeature: echte Online-Bestellstrecke

Der historische USP „erster Online-Döner" bekommt endlich gute UX:

- Jede Produktkarte hat einen **„+ Warenkorb"-Button**
- **Warenkorb-Drawer** mit Mengen-Steppern, Zwischensummen und Gesamtsumme
- **Warenkorb-Zähler** in Header und mobiler Sticky-Bar
- Abschluss ehrlich per **„Anrufen & bestellen"** oder **„Bestellung
  kopieren"** (Zusammenfassung in die Zwischenablage) — keine erfundene
  Bezahlstrecke; alles läuft lokal im Browser
- Vollständig tastatur- und screenreader-bedienbar (Dialog-Rolle,
  Fokus-Management, ESC schließt)

## Weitere Features

- Service-Chips „Vor Ort · Abholung · Lieferung"
- **Standort-Umschalter Clausthal ⇄ Zellerfeld** (eigene Adresse/Zeiten)
- Dynamischer Öffnungsstatus („Jetzt geöffnet · 11:15 – 21:30")
- Tabbed Speisekarte mit „Beliebt"-Bändern, XL-/Veggie-Tags, LMIV-Allergenen
- Trust-Element „4,5 ★ · 1.089 Bewertungen" (exakt dargestellt, nicht als
  volle 5 Sterne)
- Dark-/Light-Mode, JSON-LD Restaurant-Schema, Impressum/Datenschutz,
  Skip-Link, `prefers-reduced-motion`, WCAG-AA-Kontraste

## Vor dem Livegang (vom Betreiber zu erledigen)

- Öffnungszeiten prüfen — verwendet werden 11:15–21:30 (aus dem Briefing);
  öffentliche Verzeichnisse nennen teils 11:00–22:30
- Adresse/Hausnummer, Telefon und Lieferzeiten der **Zellerfeld/
  Brauhausberg**-Filiale ergänzen (im Standort-Umschalter als Platzhalter
  markiert)
- Impressum und Datenschutzerklärung vervollständigen (Platzhalter markiert)
- Echte Fotos ergänzen: Zekai am Spieß, die gebrandeten Serra-Boxen,
  beide Läden
- Google Business Profile mit denselben NAP-Daten verknüpfen

## Deployment

`index.html` auf einen beliebigen Webserver / CDN laden — keine Buildschritte,
keine Abhängigkeiten.

## Kontakt Restaurant

- **Clausthal (Stammhaus):** Osteröder Str. 4A, 38678 Clausthal-Zellerfeld
- **Zellerfeld (Lieferküche):** Brauhausberg, 38678 Clausthal-Zellerfeld
- **Telefon:** 05323 715350
- **Inhaber:** Zekai Ayvaz
- **Öffnungszeiten:** täglich 11:15–21:30 Uhr
- **Angebot:** Döner, Pizza, Burger · Vor Ort · Abholung · Lieferung · seit 2005
