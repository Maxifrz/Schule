# Restaurant Poseidon Astfeld — Website

Standalone Landing-Page für das griechische Restaurant Poseidon in
Langelsheim-Astfeld.

## Struktur

- `index.html` — komplett eigenständig, keine externen Assets, keine
  Font-CDNs, keine JS-Frameworks

## Features

- Animierter Wellen-Hero auf Canvas (thematisch zum Namen)
- Die drei Kernfragen (Was? Wann? Wo?) direkt above the fold:
  dynamischer Öffnungsstatus ("Heute geöffnet bis 22:00 Uhr"),
  klickbare Adresse und Telefonnummer im Hero
- Zwei CTAs im Hero (primär "Tisch reservieren", sekundär Speisekarte),
  mind. 48 px hoch; "Reservieren"-Button dauerhaft in der Navigation
- Sticky Bottom-Bar auf Mobilgeräten (Speisekarte + Reservieren)
- Tabbed Speisekarte (Vorspeisen, Hauptgerichte, Meeresfrüchte, Salate)
  mit Preisen, appetitanregenden Beschreibungen, Vegetarisch-/Vegan-Badges
  und Allergenkennzeichnung nach LMIV inkl. ausklappbarer Legende
- Öffnungszeiten mit automatischer Hervorhebung des heutigen Tags
- Kontakt- und Anfahrts-Block mit Google-Maps-Link
- Mobile Hamburger-Navigation
- Dark-/Light-Mode über `prefers-color-scheme`
- JSON-LD Restaurant-Schema für Rich Results (inkl. priceRange,
  acceptsReservations, Öffnungszeiten)
- Impressum- und Datenschutz-Abschnitte im Footer (Pflichtangaben als
  markierte Platzhalter — vor Veröffentlichung vom Betreiber ausfüllen!)
- Link zu Google-Bewertungen als Social Proof
- Skip-Link und Tab-Navigation per Pfeiltasten für Barrierefreiheit
- `prefers-reduced-motion`-Fallback (statisches Wellenbild)

## Vor dem Livegang (vom Betreiber zu erledigen)

- Impressum und Datenschutzerklärung im Footer vervollständigen
  (Platzhalter sind mit "[Vom Betreiber zu ergänzen: …]" markiert)
- Echte Food-Fotos vom eigenen Fotografen ergänzen — der Canvas-Hero
  ist ein stilvoller Platzhalter, aber "Menschen bestellen mit den Augen"
- Speisekarte, Preise und Allergenkennzeichnung mit der Küche abgleichen
- Google Business Profile mit denselben NAP-Daten (Name, Adresse,
  Telefonnummer) verknüpfen

## Deployment

Einfach `index.html` auf einen beliebigen Webserver / CDN laden —
keine Buildschritte, keine Abhängigkeiten.

## Kontakt Restaurant

- **Adresse:** Goslarsche Str. 50, 38685 Langelsheim-Astfeld
- **Telefon:** +49 5326 9699445
- **Öffnungszeiten:** Mo, Mi–So 12:00–14:00 und 17:00–22:00, Di Ruhetag
