# Restaurant Poseidon Astfeld — Website

Standalone Landing-Page für das griechische Restaurant Poseidon in
Langelsheim-Astfeld.

## Struktur

- `index.html` — komplett eigenständig, keine externen Assets, keine
  Font-CDNs, keine JS-Frameworks

## Features

- Animierter Wellen-Hero auf Canvas (thematisch zum Namen)
- Tabbed Speisekarte (Vorspeisen, Hauptgerichte, Meeresfrüchte, Salate)
- Öffnungszeiten mit automatischer Hervorhebung des heutigen Tags
- Kontakt- und Anfahrts-Block mit Google-Maps-Link
- Mobile Hamburger-Navigation
- Dark-/Light-Mode über `prefers-color-scheme`
- JSON-LD Restaurant-Schema für Rich Results
- Skip-Link und Tab-Navigation per Pfeiltasten für Barrierefreiheit
- `prefers-reduced-motion`-Fallback (statisches Wellenbild)

## Deployment

Einfach `index.html` auf einen beliebigen Webserver / CDN laden —
keine Buildschritte, keine Abhängigkeiten.

## Kontakt Restaurant

- **Adresse:** Goslarsche Str. 50, 38685 Langelsheim-Astfeld
- **Telefon:** +49 5326 9699445
- **Öffnungszeiten:** Mo, Mi–So 12:00–14:00 und 17:00–22:00, Di Ruhetag
