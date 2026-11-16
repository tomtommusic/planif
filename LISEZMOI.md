# Planif — app iPhone (SwiftUI + widget)

Version 0.1 : première version native de Planif, faite à partir de la version web.

## Ce qu'il te faut

- **Un Mac à puce Apple** (M1 ou plus récent) avec **macOS Tahoe 26.6 ou plus récent**. Xcode 27 ne fonctionne pas sur les Mac Intel.
- **Xcode 27**, gratuit dans le Mac App Store.
- Ton **compte Apple Developer** payant, nécessaire pour TestFlight.
- Un iPhone sous **iOS 26 ou plus récent**. Pour la lecture intelligente des documents, il faut aussi un iPhone 15 Pro ou plus récent avec Apple Intelligence activé. Sinon, Planif utilise une détection de dates plus simple.

## 1. Ouvrir le projet

1. Dézippe `PlanifiOS.zip`.
2. Double-clique sur `Planif.xcodeproj`.

## 2. Signature (à faire une seule fois)

1. Dans la colonne de gauche, clique sur **Planif**, l'icône bleue tout en haut.
2. Choisis la cible **Planif**, puis l'onglet **Signing & Capabilities**.
3. **Team** : choisis ton équipe de développeur.
4. Refais les étapes 2 et 3 pour la cible **PlanifWidgetExtension**.
5. Dans les deux cibles, sous **App Groups**, vérifie que `group.ca.tomtommusic.planif` est coché. S'il est en rouge, clique sur la flèche de rafraîchissement : c'est ce groupe qui permet au widget de lire tes données.

**Si Xcode dit que l'identifiant `ca.tomtommusic.planif` est déjà pris**, remplace-le partout par un autre, par exemple `ca.tomtommusic.planifapp` :
- Bundle Identifier de la cible Planif → `ca.tomtommusic.planifapp`
- Bundle Identifier de la cible PlanifWidgetExtension → `ca.tomtommusic.planifapp.widget`
- App Group dans `Planif.entitlements` et `PlanifWidget.entitlements` → `group.ca.tomtommusic.planifapp`
- La ligne `static let groupeApp = …` dans `Shared/Model.swift` → la même valeur

## 3. Essayer sur ton iPhone (le plus rapide)

1. Branche l'iPhone au Mac avec un câble et accepte « Faire confiance ».
2. Sur l'iPhone, active **Réglages → Confidentialité et sécurité → Mode développeur**. L'iPhone redémarre.
3. Dans Xcode, en haut, choisis ton iPhone comme destination, puis appuie sur **⌘R**.

**S'il y a des erreurs de compilation**, ouvre le navigateur des problèmes (⌘5) et copie-moi le texte des erreurs rouges, avec le nom du fichier. Je corrige.

## 4. Envoyer dans TestFlight

1. Va sur [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **Nouvelle app**.
   - Plateforme : iOS
   - Nom : Planif. Le nom doit être unique sur l'App Store : s'il est pris, essaie par exemple « Planif – agenda enseignant ».
   - Langue principale : français (Canada)
   - Identifiant de paquet : `ca.tomtommusic.planif`
   - SKU : `planif`
2. Dans Xcode, en haut, choisis la destination **Any iOS Device (arm64)**.
3. Va dans **Product → Archive**. À la fin, l'Organizer s'ouvre.
4. Clique sur **Distribute App → App Store Connect → Upload** et garde les options par défaut.
5. Le traitement de la version prend de quelques minutes à une demi-heure. Ensuite, dans App Store Connect → ton app → **TestFlight**, ajoute-toi comme testeur interne.
6. Sur l'iPhone, installe l'app **TestFlight** et installe Planif à partir de là.

Le réglage sur le chiffrement est déjà fait (`ITSAppUsesNonExemptEncryption = NO`) : Apple ne te posera pas la question à chaque envoi.

Pour chaque nouvelle version, augmente **Build** de 1 (cible Planif → General) avant d'archiver.

## Ce qu'il y a dans cette version

- **Assistant de départ** : cycle de 5, 9, 10 jours ou autre, cycle qui suit la semaine ou non, périodes, année scolaire, groupes.
- **Grille du cycle** : touche un groupe puis les cases, ou glisse-le. Glisser une case remplie la déplace ou l'échange avec une autre.
- **Agenda** en Semaine, Jour et Liste. Chaque cours d'une activité indique « Cours 2 sur 6 » et l'étape en cours. Toucher un cours permet d'ajouter une note ou de marquer « Pas de cours », ce qui décale la planification.
- **Activités** avec étapes et nombre de périodes, qui se placent toutes seules dans les périodes des groupes. On peut les réordonner, cocher les étapes et suivre la progression.
- **Journées sans école** (pédagos, congés, congés fériés du Québec en un bouton) qui décalent le cycle.
- **Événements**, uniques ou répétés chaque semaine ou selon le cycle.
- **Importer un document** (PDF ou photos), lu entièrement sur l'iPhone. Vision extrait le texte, puis Apple Intelligence trouve les dates quand c'est disponible. Sinon, une détection simple des dates prend le relais. Tu coches ce que tu gardes avant l'ajout.
- **Widget** petit, moyen ou grand : la période en cours avec une barre de progression, ce qui est planifié et la suite de la journée. Il fonctionne aussi en mode Transparent ou Teinté.

## Pas encore dans cette version

- Les équipes de travail (c'est dans la version web).
- La synchronisation iCloud entre appareils : pour l'instant, les données restent sur l'iPhone.
- L'import d'un horaire en grille à partir d'une photo.
- Aucun lien avec les données de la version web : il faut tout reconfigurer dans l'app.

## Organisation du code

- `Shared/` : modèle de données, calcul du cycle et de la planification, couleurs. Ce code est partagé par l'app et le widget.
- `Planif/` : les écrans de l'app.
- `PlanifWidget/` : le widget.
- `Planif/AnalyseIA.swift` : l'analyse par Apple Intelligence. Si ce fichier bloque la compilation, tu peux le supprimer : l'import utilisera la détection simple.
