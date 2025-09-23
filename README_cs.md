# BeamNG_tweakUI

## Bell 407 Surveying Autopilot – uživatelský návod

Tato aplikace do UI BeamNG.drive umožňuje konfigurovat průzkumný autopilot pro vrtulník Bell 407. Následující kroky popisují instalaci dílu, nastavení navigačního targetu, vyplnění parametrů a spuštění/ukončení průletu.

### 1. Příprava hardware
1. Otevři **Vehicle Config** → *Frame* → *Electronics* a do slotu **Surveying Autopilot** nainstaluj díl `bell_survey_autopilot` (pokud už není aktivní).
2. Pokud aplikace hlásí „Surveying Autopilot hardware not detected“, díl není v aktuální konfiguraci přítomen – doplň jej a UI znovu načti.

### 2. Nastavení navigačního targetu
1. V herním světě otevři mapu (standardně klávesou **M**) a kliknutím nastav navigační target – interně se uloží jako *ground marker*, který aplikace načítá přes `core_groundMarkers.getTargetPos()`.
2. V aplikaci stiskni **Use Navigation Target**; tím se target překlopí na startovní bod vzoru. Pokud žádný target není zvolen, zobrazí se chyba a autopilot nepůjde vyzbrojit.
3. Alternativně lze tlačítkem **Load Home Position** načíst domovskou pozici helikoptéry (spawn point); pokud ještě nemáš vybraný start, vyplní se automaticky.

### 3. Konfigurace parametrů v UI
Parametry se nacházejí v panelu **Survey Pattern**. Všechny změny vyvolají nový náhled tratě v pravém panelu.

| Pole | Význam |
|------|--------|
| **Altitude (m)** | Letová hladina celého průletu; do plánu se přepisuje také startovní bod. |
| **Track angle (°)** | Úhel první přímky vůči severu; tvoří směr podélných úseků vzoru. |
| **Leg length (m)** | Délka každého průletu; musí být kladná, skript zajišťuje minimální délku 0,1 m. |
| **Spacing (m)** | Rozestup mezi sousedními řadami; může být záporný pro otočené odsazení. |
| **Rows** | Počet průletů (řad) ve vzoru; minimálně 1. |
| **Survey speed (m/s)** | Cílová rychlost při měřicích průletech. |
| **Finish behavior** | Režim dokončení (viz kapitola 4). |
| **Transit speed (m/s)** | Volitelná rychlost přeletu na začátek vzoru; prázdné = automatika dle plánu. |

Panel **Start point** zobrazuje souřadnice startu, případně „No start point selected“. K dispozici je také status domovské pozice, pokud ji autopilot vrátí.

### 4. Dokončení a návrat
Tři režimy dokončení odpovídají hodnotám `Finish behavior`:
- **Hover at final waypoint** – vrtulník poletí poslední nohu a zůstane vyset na konci vzoru.
- **Return to start** – po dokončení vzoru se vrátí nad startovní bod, vyrovná se do hoveru a čeká na pokyny.
- **Return home and land** – po dokončení vzoru přejde na domovský bod, přistane a ukončí se.

### 5. Spouštění a zastavování autopilota
1. Zkontroluj, že je hardware detekován (vlevo nahoře) a že máš platný náhled vzoru – v mapovém panelu se vykreslí linie a startovní bod.
2. Stiskni **Arm Autopilot** – UI odešle konfiguraci a příkaz `activate`. V případě chyby se zobrazí hláška a status zůstane `Idle`.
3. Jakmile je stav `Armed`, stiskni **Start Survey** – autopilot přejde přes rozběh rotoru, vzlet, transit a začne lítat pattern.
4. Kdykoliv můžeš použít **Abort** – UI odešle `cancel` a navrátí ovládání pilotovi.
5. Po dokončení mise můžeš tlačítkem **Reset** obnovit výchozí parametry a vyčistit náhled.

Stavový panel ukazuje aktuální fázi letu, procento roztočení rotoru, rychlost a počet waypointů – podle těchto údajů lze ověřit, že skript drží správný režim.

### 6. Troubleshooting & tipy
- **Nelze armovat autopilota** – ověř, že je nainstalovaný díl a že máš nastavený navigační target; funkce `ensureReady()` požaduje jak hardware, tak ground marker a jinak vrací chyby `missingPart`/`noTarget`.
- **Náhled hlásí „Unable to compute preview.“** – zkontroluj, že startovní bod má platné souřadnice a výšku; plán se generuje z `startPoint` a parametrů, chybějící hodnoty preview odmítnou.
- **Rotor se netočí dost rychle** – autopilot čeká, dokud rotory nepřekročí ~85 % cílových RPM a neudrží je `rotorStableTime`; pokud vrtulník stojí v terénu, dej mu čas nebo odlehči kolektivem.
- **Vrtulník po návratu neodpojuje ovládání** – režim `Abort` okamžitě posílá `cancel`, což vrací autopilot do stavu `idle` a uvolní řízení.
- **Domovská pozice není k dispozici** – autopilot ji odvozuje ze spawn OOBB nebo aktuální pozice; pokud se nenačte, UI vypíše chybu a lze pokračovat bez ní.

### 7. Kompatibilita
- Skript i UI jsou navrženy pro vrtulník **Bell 407** s aktivovaným modulem `Surveying Autopilot`. Jiné stroje kontroler `407surveyAutopilot` nenajdou (`isInstalled()` vrátí `false`).
- Aplikace poslouchá datové streamy `sensors` a `electrics` BeamNG, takže je kompatibilní s výchozí telemetrií hry (žádné dodatečné módy nejsou potřeba).

### 8. Zdrojové soubory pro inspiraci
- `ui/modules/apps/bell407SurveyingAutopilot/app.html` – rozložení UI, stavové hlášky a ovládací prvky.
- `ui/modules/apps/bell407SurveyingAutopilot/app.js` – Angular controller, obsluha tlačítek a komunikace s LUA extension.
- `Bell407/vehicles/bell407/lua/surveyingAutopilot.lua` – extension běžící ve vozidle, generování plánů a API pro UI.
- `Bell407/vehicles/bell407/lua/controller/407surveyAutopilot.lua` – vlastní autopilotní kontroler zajišťující rozběh, vzor, návrat i přistání.

> Poznámka: Pokud potřebuješ screenshot UI, spusť hru, otevři aplikaci **Bell 407 Surveying Autopilot** ve vyjížděcím panelu a zachyť pravý náhledový canvas se zvoleným patternem. (V repozitáři screenshot není součástí projektu.)
