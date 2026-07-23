# MoneybirdTimer

Eenvoudige iOS-app om tijd te registreren via de [Moneybird](https://moneybird.com) API. Start en stop een timer met één druk op de knop; de time entry wordt direct in Moneybird aangemaakt.

Native SwiftUI, geen externe afhankelijkheden — alleen Apple-frameworks (`SwiftUI`, `Foundation`, `UserNotifications`, `Security`).

## Functies

- Timer starten/stoppen voor een gekozen project en gebruiker
- Recente tijdregistraties bekijken, wijzigen, hervatten en verwijderen
- **Home Screen quick actions**: houd het app-icoon ingedrukt om direct een timer te starten met het laatst gebruikte project — of een lopende timer te stoppen
- Herinnering (notificatie) als een timer langer dan 8 uur loopt
- Timer overleeft het afsluiten van de app en wordt bij herstart hervat met de juiste verstreken tijd

## Vereisten

- Xcode 15 of nieuwer
- iOS 16 of nieuwer (doelplatform)
- Een Moneybird-account met API-toegang

## Aan de slag

1. Clone de repository en open `MoneybirdTimer.xcodeproj` in Xcode.
2. Selecteer bij **Signing & Capabilities** je eigen **Team** (het project wordt zonder team geleverd) en pas eventueel de bundle identifier aan.
3. Kies een simulator of je iPhone en druk op **Run**.

## Moneybird instellen

### API-token ophalen

1. Log in op [moneybird.com](https://moneybird.com)
2. Ga naar **Instellingen → API**
3. Klik op **Nieuw token aanmaken**, geef het een naam (bijv. "MoneybirdTimer iOS") en sla op
4. Kopieer het token — het wordt maar één keer getoond

### Administratie-ID vinden

Het administratie-ID staat in de URL wanneer je bent ingelogd:

```
https://moneybird.com/123456789012345678/...
                       ^^^^^^^^^^^^^^^^^^
                       dit is jouw administratie-ID
```

### App configureren

1. Start de app en tik op het tandwiel-icoon rechtsboven
2. Vul je **API-token** en **administratie-ID** in en tik op **Opslaan**

De credentials worden veilig opgeslagen in de **Keychain** — ze staan nergens in de code of in de repository.

## Bestandsstructuur

```
MoneybirdTimer/
├── MoneybirdTimerApp.swift   – App entry point (@main) + Home Screen quick actions
├── Models.swift              – Project-, User- en TimeEntry-modellen (Codable)
├── KeychainHelper.swift      – Opslaan/uitlezen van credentials in de Keychain
├── MoneybirdAPI.swift        – Alle API-aanroepen (async/await + URLSession)
├── TimerViewModel.swift      – Centrale @MainActor ObservableObject
├── ContentView.swift         – Hoofdscherm: project/gebruiker-kiezer + timer
├── SettingsView.swift        – Instellingenscherm (credentials)
├── EditTimeEntryView.swift   – Bewerken van een tijdregistratie
└── NotificationDelegate.swift – Afhandeling van de 8-uurs notificatie
```

## Gedrag bij herstart

Als de app wordt afgesloten terwijl een timer loopt:

- De time entry ID en `started_at` worden bewaard in **UserDefaults**
- Bij herstart wordt de timer hervat met de correcte verstreken tijd
- De 8-uurs notificatie wordt opnieuw ingepland op basis van de originele starttijd

## Licentie

Zie [LICENSE](LICENSE).
