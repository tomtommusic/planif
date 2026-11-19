import SwiftUI

struct PlusView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { ActivitesView(dansPile: false) } label: { Label("Activités (planification)", systemImage: "square.stack.3d.up") }
                NavigationLink { GrilleView() } label: { Label("Horaire (grille du cycle)", systemImage: "square.grid.3x3") }
                NavigationLink { HorairesView() } label: { Label("Horaires réguliers (pratiques, soirées…)", systemImage: "repeat") }
                NavigationLink { EvenementsView() } label: { Label("Événements", systemImage: "calendar.badge.plus") }
                NavigationLink { SansEcoleView() } label: { Label("Journées sans école", systemImage: "sun.max") }
                NavigationLink { ImportView() } label: { Label("Importer un document", systemImage: "doc.viewfinder") }
                NavigationLink { ReglagesView() } label: { Label("Réglages", systemImage: "slider.horizontal.3") }
                NavigationLink { AideWidgetView() } label: { Label("Ajouter le widget", systemImage: "rectangle.3.group") }
            }
            .navigationTitle("Plus")
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
        }
    }
}

// MARK: - Événements

struct EvenementsView: View {
    @EnvironmentObject var store: Store
    @State private var aVenir = true
    @State private var nouveau = false
    @State private var choisi: Evenement?

    var body: some View {
        let t = D.today()
        let liste = store.data.evenements
            .filter { !aVenir || finEffective($0) >= t }
            .sorted { ($0.date + $0.debut) < ($1.date + $1.debut) }
        List {
            Picker("", selection: $aVenir) {
                Text("À venir").tag(true)
                Text("Tous").tag(false)
            }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
            if liste.isEmpty { Text("Aucun événement.").foregroundStyle(.secondary) }
            ForEach(liste) { e in
                Button { choisi = e } label: {
                    HStack(spacing: 12) {
                        Image(systemName: e.type.symbole).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titre).font(.headline).foregroundStyle(.primary)
                            Text(resume(e)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Événements")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { nouveau = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $nouveau) { EvenementEditeur(original: Evenement(titre: "", date: D.today())) }
        .sheet(item: $choisi) { EvenementEditeur(original: $0) }
    }

    private func finEffective(_ e: Evenement) -> String {
        if e.rec == .aucune { return e.dateFin.isEmpty ? e.date : e.dateFin }
        return e.jusquau.isEmpty ? "9999-12-31" : e.jusquau
    }

    private func resume(_ e: Evenement) -> String {
        var s = D.court(e.date)
        if !e.dateFin.isEmpty { s += " → " + D.court(e.dateFin) }
        s += e.journee ? " · journée" : " · " + D.hm(e.debut)
        if e.rec == .hebdo { s += " · chaque semaine" }
        if e.rec == .cycle { s += " · selon le cycle" }
        return s + " · " + e.type.label
    }
}

struct EvenementEditeur: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: Evenement
    @State private var e = Evenement(titre: "", date: "")
    @State private var plusieursJours = false
    @State private var pret = false

    private var existe: Bool { store.data.evenements.contains { $0.id == original.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $e.titre)
                    Picker("Type", selection: $e.type) {
                        ForEach(TypeEvenement.allCases) { Label($0.label, systemImage: $0.symbole).tag($0) }
                    }
                }
                Section {
                    DatePicker("Date", selection: liaisonDate($e.date), displayedComponents: .date)
                    if e.rec == .aucune {
                        Toggle("Plusieurs jours", isOn: $plusieursJours)
                        if plusieursJours { DatePicker("Jusqu’au", selection: liaisonDate($e.dateFin), displayedComponents: .date) }
                    }
                    Toggle("Toute la journée", isOn: $e.journee)
                    if !e.journee {
                        DatePicker("Début", selection: liaisonHeure($e.debut), displayedComponents: .hourAndMinute)
                        DatePicker("Fin", selection: liaisonHeure($e.fin, defaut: "09:00"), displayedComponents: .hourAndMinute)
                    }
                }
                Section("Répéter") {
                    Picker("Répéter", selection: $e.rec) { ForEach(Recurrence.allCases) { Text($0.label).tag($0) } }
                    if e.rec == .hebdo {
                        ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { j in
                            Toggle(D.jourLong[j].capitalized, isOn: jour(j))
                        }
                        Toggle("Seulement les jours d’école", isOn: $e.ecoleSeulement)
                    }
                    if e.rec == .cycle {
                        ForEach(1...store.moteur.L, id: \.self) { j in
                            Toggle(store.moteur.etiquetteJour(j), isOn: jour(j))
                        }
                    }
                    if e.rec != .aucune {
                        DatePicker("Jusqu’au", selection: liaisonDate($e.jusquau), displayedComponents: .date)
                    }
                }
                Section {
                    TextField("Lieu", text: $e.lieu)
                    TextField("Note", text: $e.note, axis: .vertical).lineLimit(2...5)
                    Toggle("Pas de cours ce jour-là (décale la planif)", isOn: $e.annuleCours)
                } footer: {
                    Text("Les congés et les journées pédagogiques ne comptent pas dans le cycle.")
                }
                if existe {
                    Section {
                        Button("Supprimer l’événement", role: .destructive) {
                            let id = e.id
                            store.maj { d in d.evenements.removeAll { $0.id == id } }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existe ? "Modifier l’événement" : "Nouvel événement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var x = e
                        x.titre = x.titre.trimmingCharacters(in: .whitespaces)
                        if x.rec != .aucune || !plusieursJours || x.dateFin <= x.date { x.dateFin = "" }
                        if x.journee { x.debut = ""; x.fin = "" }
                        if x.rec == .aucune { x.jours = []; x.jusquau = "" }
                        store.maj { d in
                            if let i = d.evenements.firstIndex(where: { $0.id == x.id }) { d.evenements[i] = x } else { d.evenements.append(x) }
                        }
                        dismiss()
                    }
                    .disabled(e.titre.trimmingCharacters(in: .whitespaces).isEmpty || (e.rec != .aucune && e.jours.isEmpty))
                }
            }
            .onAppear {
                guard !pret else { return }
                pret = true
                e = original
                plusieursJours = !e.dateFin.isEmpty
                if e.jusquau.isEmpty { e.jusquau = store.data.config.fin }
                if e.dateFin.isEmpty { e.dateFin = e.date }
            }
        }
    }

    private func jour(_ j: Int) -> Binding<Bool> {
        Binding(get: { e.jours.contains(j) }, set: { on in if on { e.jours.append(j) } else { e.jours.removeAll { $0 == j } } })
    }
}

// MARK: - Journées sans école

struct SansEcoleView: View {
    @EnvironmentObject var store: Store
    @State private var type: TypeEvenement = .pedago
    @State private var date = D.today()
    @State private var plusieurs = false
    @State private var fin = D.today()
    @State private var nom = ""
    @State private var message: String?

    var body: some View {
        let m = store.moteur
        let liste = m.sansEcole
        let feries = m.feriesQuebec().filter { f in !liste.contains { $0.date == f.1 } }
        Form {
            Section {
                Text("Planif compte les jours d’école pour trouver le jour du cycle. Chaque journée pédagogique ou congé saute un jour : le cycle reprend où il était le lendemain.")
                    .font(.footnote)
            }
            Section("Ajouter") {
                Picker("Type", selection: $type) {
                    Text("Journée pédagogique").tag(TypeEvenement.pedago)
                    Text("Congé").tag(TypeEvenement.conge)
                }
                .pickerStyle(.segmented)
                DatePicker("Date", selection: liaisonDate($date), displayedComponents: .date)
                Toggle("Plusieurs jours (Fêtes, relâche)", isOn: $plusieurs)
                if plusieurs { DatePicker("Jusqu’au", selection: liaisonDate($fin), displayedComponents: .date) }
                TextField("Nom (optionnel)", text: $nom)
                Button("Ajouter") {
                    let titre = nom.trimmingCharacters(in: .whitespaces).isEmpty ? type.label : nom
                    var ok = false
                    store.maj { d in ok = store.ajouterSansEcole(titre, date: date, fin: plusieurs ? fin : "", type: type, dans: &d) }
                    message = ok ? "Ajouté : le cycle est recalculé." : "Cette date est déjà inscrite."
                    nom = ""
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            if !feries.isEmpty {
                Section {
                    ForEach(Array(feries.enumerated()), id: \.offset) { _, f in Text("\(f.0) — \(D.court(f.1))") }
                    Button("Ajouter ces \(feries.count) congés") {
                        store.maj { d in for f in feries { _ = store.ajouterSansEcole(f.0, date: f.1, fin: "", type: .conge, dans: &d) } }
                    }
                } header: { Text("Congés fériés du Québec") } footer: {
                    Text("Le congé des Fêtes et la relâche varient selon le centre de services : ajoute-les ci-dessus avec « Plusieurs jours ».")
                }
            }
            Section("\(liste.count) journée(s) inscrite(s)") {
                ForEach(liste) { e in
                    HStack {
                        Image(systemName: e.type.symbole).frame(width: 26)
                        VStack(alignment: .leading) {
                            Text(D.court(e.date) + (e.dateFin.isEmpty ? "" : " → " + D.court(e.dateFin))).bold()
                            Text(e.titre == e.type.label ? e.titre : e.titre + " · " + e.type.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { liste[$0].id }
                    store.maj { d in d.evenements.removeAll { ids.contains($0.id) } }
                }
            }
        }
        .navigationTitle("Journées sans école")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
    }
}

// MARK: - Réglages

struct ReglagesView: View {
    @EnvironmentObject var store: Store
    @State private var config = Config(debut: "", fin: "", refDate: "")
    @State private var choix = 9
    @State private var pret = false
    @State private var enregistre = false
    @State private var recommencer = false

    var body: some View {
        Form {
            Section { TextField("Nom de l’école", text: $config.ecole) }
            ReglagesCycle(config: $config, choix: $choix)
            Section("Année scolaire") {
                DatePicker("Premier jour", selection: liaisonDate($config.debut), displayedComponents: .date)
                DatePicker("Dernier jour", selection: liaisonDate($config.fin), displayedComponents: .date)
                if !config.hebdo {
                    DatePicker("Une date connue", selection: liaisonDate($config.refDate), displayedComponents: .date)
                    Stepper("Son jour de cycle : \(config.refJour)", value: $config.refJour, in: 1...max(1, config.cycleLen))
                }
                if !store.data.config.cycleMap.isEmpty {
                    Button("Effacer les \(store.data.config.cycleMap.count) jours fixés à la main", role: .destructive) {
                        store.maj { d in d.config.cycleMap = [:] }
                        config.cycleMap = [:]
                    }
                }
            }
            Section {
                Button("Enregistrer") {
                    let c = config
                    store.maj { d in
                        let map = d.config.cycleMap
                        d.config = c
                        d.config.cycleMap = map
                        d.config.onboarded = true
                        nettoyerGrille(&d)
                    }
                    enregistre = true
                }
                .disabled(config.fin < config.debut)
                if enregistre { Text("Réglages enregistrés.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                NavigationLink("Journées pédagogiques et congés") { SansEcoleView() }
                ShareLink(item: exportJSON(), preview: SharePreview("Sauvegarde Planif")) { Label("Exporter une sauvegarde", systemImage: "square.and.arrow.up") }
            } footer: {
                Text("Tes données restent sur cet iPhone. La sauvegarde est un fichier texte que tu peux garder ailleurs.")
            }
            Section {
                Button("Refaire l’assistant de départ") { recommencer = true }
            }
        }
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
        .confirmationDialog("Refaire l’assistant? Tes groupes, ta grille et tes activités sont conservés.", isPresented: $recommencer, titleVisibility: .visible) {
            Button("Refaire l’assistant") { store.maj { d in d.config.onboarded = false } }
        }
        .onAppear {
            guard !pret else { return }
            pret = true
            config = store.data.config
            choix = [5, 9, 10].contains(config.cycleLen) ? config.cycleLen : 0
        }
    }

    private func exportJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(store.data) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct AideWidgetView: View {
    var body: some View {
        List {
            Section("Ajouter le widget Planif") {
                Label("Sur l’écran d’accueil, garde le doigt sur un espace vide jusqu’à ce que les icônes bougent.", systemImage: "1.circle")
                Label("Touche « Modifier », puis « Ajouter un widget ».", systemImage: "2.circle")
                Label("Cherche « Planif » et choisis la taille : petit, moyen ou grand.", systemImage: "3.circle")
            }
            Section("Ce que montre le widget") {
                Text("La période en cours, avec une barre qui avance jusqu’à la fin du cours, ce qui est planifié (« Cours 2 sur 6 ») et la suite de la journée.")
                Text("Le style transparent ou teinté se choisit dans « Personnaliser » sur l’écran d’accueil d’iOS. Le nom du groupe reste toujours écrit.")
            }
        }
        .navigationTitle("Widget")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
    }
}
