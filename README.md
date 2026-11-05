# Guildon: Crafts & Recipes 1.2.2 (WoW Forever und WoW Classic Era)

Handwerk der Gilde: Berufe und Rezepte der Gilde, Wunschliste mit Aufträgen, Hilfe bei Handel und Post, geteilte Auktionspreise
und profitable Rezepte. Teil von Guildon, den Addons für die Gilde; bis Guildon 0.8 war es der Berufsteil von Guildon. Alle Guildon-Teile teilen sich
einen Knopf an der Minikarte.
Für World of Warcraft: Forever (Client "Camelot", Interface 16001) und WoW Classic Era (Interface 11509).
Alles läuft zwischen Mitgliedern, die Guildon Crafts haben, über den Addon-Kanal der Gilde. Es gibt keinen Server.

## Installation
Ordner `Guildon_Crafts` in den AddOns-Ordner des Clients kopieren (`...\Interface\AddOns\`). Guildon Crafts läuft allein; Guildon: Map & Members 0.9 braucht
Guildon Crafts und zeigt dann die Berufe im Mitglieder-Tooltip.

## Von Guildon 0.8 kommend
- Beim ersten Start übernimmt Guildon Crafts aus Guildon deine Berufe, Rezepte, Wünsche und Aufträge, Preise, Abklingzeiten, gesuchte
  Rezepte, den Dankzähler und die Berufs-Optionen. Guildons Daten bleiben, wie sie sind.
- Mitglieder, die noch Guildon 0.8 haben, sieht Guildon Crafts weiter: es liest ihre Berufe und Wünsche mit und schickt ihnen deine.

## Funktionen
- **Berufe und Rezepte der Gilde:** die Berufe jedes Mitglieds mit Fertigkeit, alle Rezepte eines Berufs mit Haken, wer in der
  Gilde es herstellen kann (grün, wenn jemand online ist), Suche, Filter, Gruppen nach Art (Rüstung nach Platz, Essen nach Buff),
  Reagenzien mit dem, was du hast, Flüstern an den Handwerker mit Gegenstandslink.
- **Wunschliste:** ein Rezept wünschen statt herumzufragen: Menge, "Mats habe ich", "Mats bezahle ich" oder "knapp bei Kasse",
  Trinkgeld, Notiz, für alle oder einen Handwerker. Handwerker sehen, was sie herstellen können, nehmen an, melden hergestellt und
  verschickt. Nach dem Handel oder dem Öffnen des Briefs gilt der Wunsch als erhalten. Wünsche für Sammelgut erreichen die Sammler
  der Gilde. Offiziere dürfen Wünsche löschen, der Gildenleiter wählt die Ränge.
- **Handel und Post:** eine Leiste unter dem Handelsfenster und im Reiter Senden des Briefkastens legt Mats oder Ware eines
  Auftrags ein (ein Stapel je Klick), füllt den Brief aus und setzt die Nachnahme. Handel annehmen und Brief abschicken machst du selbst.
- **Preise und profitable Rezepte:** Preise aus Auctionator, Auctioneer oder aux werden mit der Gilde geteilt (der neueste Scan
  zählt, Ausreißer sind markiert). Ohne AH-Addon ein kurzer Scan im Auktionshaus. Der Reiter Profitabel (in den Optionen
  einschalten) ordnet Rezepte nach Gewinn je Herstellung.
- **Und mehr:** Abklingzeiten der Gilde (Transmutieren, Mondstoff, Salzstreuer), "Rezept gesucht" mit Tooltipzeilen auf
  Rezeptgegenständen und einer Meldung, wenn es bei dir droppt, Einkaufslisten, Hinweis, wenn ein Handwerker für deinen Wunsch
  online kommt, Dankzähler, "In der Gilde hergestellt von" im Gegenstands-Tooltip, Export deiner Berufe für die Gildenseite.
- **Allein ausprobieren:** `/gnc demo` zeigt eine Beispielgilde, nur auf deinem Bildschirm.
- Englisch, Deutsch, Französisch, Spanisch (Spanien und Lateinamerika), brasilianisches Portugiesisch, Russisch, Koreanisch und
  traditionelles Chinesisch.

## Befehle
- `/gnc` (oder `/guildoncrafts`) Fenster zeigen oder ausblenden (auch über den Knopf an der Minikarte)
- `/gnc wishes` Wunschliste
- `/gnc options` alle Einstellungen im gemeinsamen Optionsfenster der Don-Addons (auch das Zahnrad im Fenster)
- `/gnc sync` die Gilde jetzt nach neuen Daten fragen
- `/gnc demo` Beispielgilde (nochmal: aus)
- `/gnc export` deine Berufe als Text für die Gildenseite
- `/gnc recipes` Rezepte, die das Spiel gezeigt hat und Guildon Crafts noch nicht kennt, als Text für die Autoren
- `/gnc diag` Stand des Austauschs und Fehler
- `/gnc help` alle Befehle

## Technik
- Austausch nur über Addon-Nachrichten im Gildenkanal (Präfix "Guildon Crafts", auf Era "GuildonCraftsEra"), Daten in Stücken mit
  Prüfsumme, abgeholt per Flüstern. In der Übergangszeit auch unter "Guildon" mit Mitgliedern auf Guildon 0.8.
- Handel und Post: Guildon Crafts legt Gegenstände nur nach deinem Klick ein. Annehmen und Senden bleiben bei dir.
- Preise der AH-Addons über deren öffentliche Schnittstellen, jeder Aufruf geschützt (pcall).
- Rezeptdaten aus All The Things (MIT) und CMaNGOS classic-db (GPL v3), für Forever und Era. Lager-Rezepte für Forever: Data from
  ForeverDB.net (https://foreverdb.net), GPL v3.

## Lizenz
Code: MIT, siehe LICENSE.txt. Rezeptdaten (Data/Recipes.lua, DataEra/Recipes.lua): GPL v3, weil sie aus CMaNGOS gebaut sind, Text
in Data/Recipes-LICENSE-GPLv3.txt. Das Addon als Ganzes steht damit unter GPL v3. Autor: DonCoohd.
