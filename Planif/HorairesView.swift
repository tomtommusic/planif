import SwiftUI

// MARK: - Horaires réguliers : un 2e horaire (pratiques, soirées…) jumelé à l'horaire de cours

struct HorairesView: View {
    @EnvironmentObject var store: Store
    @State private var choisi: HoraireSup?

    var body: some View {
        List {
            Section {
                Text("Ajoute ici ce qui revient chaque semaine en dehors de ta grille de cours : pratiques de bands, surveillances, activités du soir… Tout apparaît dans l’agenda et le widget, à côté de tes cours.")
                    .font(.footnote)
            }
            if store.data.horaires.isEmpty {
                Text("Aucun horaire régulier.").foregroundStyle(.secondary)
            }
            ForEach(store.data.horaires) { h in
                Button { choisi = h } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.nom).font(.headline).foregroundStyle(.primary)
                        Text(HoraireTexte.resume(h, store.moteur)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button {
                    choisi = HoraireSup(nom: "", debut: max(D.today(), store.data.config.debut), fin: store.data.config.fin)
                } label: { Label("Nouvel horaire régulier", systemImage: "plus") }
            }
        }
        .navigationTitle("Horaires réguliers")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
        .sheet(item: $choisi) { HoraireEditeur(original: $0) }
    }
}

enum HoraireTexte {
    static func jours(_ jours: [Int], _ rec: Recurrence, _ m: Moteur) -> String {
        if rec == .cycle {
            return jours.sorted().map { m.etiquetteJour($0) }.joined(separator: ", ")
        }
        let ordre = [1, 2, 3, 4, 5, 6, 0]
        return ordre.filter { jours.contains($0) }.map { D.jourLong[$0] }.joined(separator: ", ")
    }

    static func bloc(_ b: BlocHoraire, _ rec: Recurrence, _ m: Moteur) -> String {
        let j = jours(b.jours, rec, m)
        return (j.isEmpty ? "aucun jour" : j) + " · " + D.hm(b.debut) + "–" + D.hm(b.fin) + (b.lieu.isEmpty ? "" : " · " + b.lieu)
    }

    static func resume(_ h: HoraireSup, _ m: Moteur) -> String {
        let n = h.blocs.count
        return "\(n) plage\(n > 1 ? "s" : "") · " + (h.rec == .cycle ? "selon le cycle" : "chaque semaine")
            + " · jusqu’au " + D.court(h.fin)
    }
}

struct HoraireEditeur: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: HoraireSup
    @State private var h = HoraireSup(nom: "", debut: "", fin: "")
    @State private var pret = false
    @State private var bloc: BlocHoraire?

    private var existe: Bool { store.data.horaires.contains { $0.id == original.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex. : Pratiques de bands)", text: $h.nom)
                    Picker("Répéter", selection: $h.rec) {
                        Text("Chaque semaine").tag(Recurrence.hebdo)
                        Text("Selon les jours du cycle").tag(Recurrence.cycle)
                    }
                    if h.rec == .hebdo {
                        Toggle("Seulement les jours d’école", isOn: $h.ecoleSeulement)
                    }
                    DatePicker("Du", selection: liaisonDate($h.debut), displayedComponents: .date)
                    DatePicker("Au", selection: liaisonDate($h.fin), displayedComponents: .date)
                } footer: {
                    Text(h.rec == .cycle || h.ecoleSeulement
                         ? "Rien n’est affiché les jours de congé et les journées pédagogiques."
                         : "Affiché même les jours sans école.")
                }

                Section("Plages") {
                    if h.blocs.isEmpty {
                        Text("Ajoute une plage pour chaque activité : un band, une pratique…").foregroundStyle(.secondary)
                    }
                    ForEach(h.blocs) { b in
                        Button { bloc = b } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.titre.isEmpty ? "Sans titre" : b.titre).font(.headline).foregroundStyle(.primary)
                                Text(HoraireTexte.bloc(b, h.rec, store.moteur)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { h.blocs.remove(atOffsets: $0) }
                    Button {
                        let dernier = h.blocs.last
                        bloc = BlocHoraire(titre: "", jours: [], debut: dernier?.debut ?? "18:30", fin: dernier?.fin ?? "20:00", lieu: dernier?.lieu ?? "")
                    } label: { Label("Ajouter une plage", systemImage: "plus") }
                }

                if !h.blocs.isEmpty {
                    Section("Aperçu") {
                        ForEach(apercu, id: \.0) { ligne in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ligne.0).font(.subheadline.bold())
                                ForEach(ligne.1, id: \.self) { Text($0).font(.caption) }
                            }
                        }
                    }
                }

                let annulees = h.exceptions.sorted { $0.split(separator: "|").last ?? "" < $1.split(separator: "|").last ?? "" }
                if !annulees.isEmpty {
                    Section {
                        ForEach(annulees, id: \.self) { ex in
                            HStack {
                                Text(texteException(ex)).font(.subheadline)
                                Spacer()
                                Button("Rétablir") { h.exceptions.removeAll { $0 == ex } }.font(.caption.bold())
                            }
                        }
                    } header: { Text("Annulées") }
                }

                if existe {
                    Section {
                        Button("Supprimer cet horaire", role: .destructive) {
                            let id = h.id
                            store.maj { d in d.horaires.removeAll { $0.id == id } }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existe ? "Modifier l’horaire" : "Nouvel horaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var x = h
                        x.nom = x.nom.trimmingCharacters(in: .whitespaces)
                        if x.fin < x.debut { x.fin = x.debut }
                        store.maj { d in
                            if let i = d.horaires.firstIndex(where: { $0.id == x.id }) { d.horaires[i] = x } else { d.horaires.append(x) }
                        }
                        dismiss()
                    }
                    .disabled(h.nom.trimmingCharacters(in: .whitespaces).isEmpty || h.blocs.isEmpty)
                }
            }
            .sheet(item: $bloc) { b in
                BlocEditeur(original: b, rec: h.rec,
                            enregistrer: { nb in
                                if let i = h.blocs.firstIndex(where: { $0.id == nb.id }) { h.blocs[i] = nb } else { h.blocs.append(nb) }
                            },
                            supprimer: { id in h.blocs.removeAll { $0.id == id } })
            }
            .onAppear {
                guard !pret else { return }
                pret = true
                h = original
            }
        }
    }

    /// Plages regroupées par jour, dans l'ordre de la semaine (ou du cycle).
    private var apercu: [(String, [String])] {
        let m = store.moteur
        let ordre = h.rec == .cycle ? Array(1...max(1, m.L)) : [1, 2, 3, 4, 5, 6, 0]
        return ordre.compactMap { j in
            let bs = h.blocs.filter { $0.jours.contains(j) }.sorted { $0.debut < $1.debut }
            guard !bs.isEmpty else { return nil }
            let nom = h.rec == .cycle ? m.etiquetteJour(j) : D.jourLong[j].capitalized
            return (nom, bs.map { D.hm($0.debut) + "–" + D.hm($0.fin) + "  " + ($0.titre.isEmpty ? "Sans titre" : $0.titre) })
        }
    }

    private func texteException(_ ex: String) -> String {
        let p = ex.split(separator: "|").map(String.init)
        guard p.count == 2 else { return ex }
        let titre = h.blocs.first { $0.id == p[0] }?.titre ?? "Plage supprimée"
        return D.court(p[1]) + " · " + titre
    }
}

struct BlocEditeur: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: BlocHoraire
    let rec: Recurrence
    let enregistrer: (BlocHoraire) -> Void
    let supprimer: (String) -> Void
    @State private var b = BlocHoraire(titre: "")
    @State private var pret = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre (ex. : Band des sec. 4)", text: $b.titre)
                    TextField("Lieu", text: $b.lieu)
                }
                Section {
                    DatePicker("Début", selection: liaisonHeure($b.debut), displayedComponents: .hourAndMinute)
                    DatePicker("Fin", selection: liaisonHeure($b.fin, defaut: "20:00"), displayedComponents: .hourAndMinute)
                }
                Section(rec == .cycle ? "Jours du cycle" : "Jours") {
                    if rec == .cycle {
                        ForEach(1...max(1, store.moteur.L), id: \.self) { j in
                            Toggle(store.moteur.etiquetteJour(j), isOn: jour(j))
                        }
                    } else {
                        ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { j in
                            Toggle(D.jourLong[j].capitalized, isOn: jour(j))
                        }
                    }
                }
                if !original.titre.isEmpty || !original.jours.isEmpty {
                    Section {
                        Button("Supprimer la plage", role: .destructive) {
                            supprimer(b.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Plage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        var x = b
                        x.titre = x.titre.trimmingCharacters(in: .whitespaces)
                        if x.fin < x.debut { x.fin = x.debut }
                        enregistrer(x)
                        dismiss()
                    }
                    .disabled(b.titre.trimmingCharacters(in: .whitespaces).isEmpty || b.jours.isEmpty)
                }
            }
            .onAppear {
                guard !pret else { return }
                pret = true
                b = original
            }
        }
        .presentationDetents([.large])
    }

    private func jour(_ j: Int) -> Binding<Bool> {
        Binding(get: { b.jours.contains(j) }, set: { on in if on { b.jours.append(j) } else { b.jours.removeAll { $0 == j } } })
    }
}

/// Tap sur une pratique dans l'agenda : annuler cette fois-ci ou modifier l'horaire.
struct OccurrenceSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let occ: Evenement
    @State private var edition: HoraireSup?

    var body: some View {
        let h = store.data.horaires.first { $0.id == occ.horaireId }
        NavigationStack {
            Form {
                Section {
                    Label(occ.titre, systemImage: "repeat").font(.title3.bold())
                    Text(D.long(occ.date)).font(.subheadline)
                    Text(D.hm(occ.debut) + "–" + D.hm(occ.fin) + (occ.lieu.isEmpty ? "" : " · " + occ.lieu))
                    if let h { Text("Horaire : " + h.nom).font(.caption).foregroundStyle(.secondary) }
                }
                if let h, let bid = occ.blocId {
                    Section {
                        Button("Annuler cette fois-ci seulement", role: .destructive) {
                            let cle = bid + "|" + occ.date
                            store.maj { d in
                                if let i = d.horaires.firstIndex(where: { $0.id == h.id }), !d.horaires[i].exceptions.contains(cle) {
                                    d.horaires[i].exceptions.append(cle)
                                }
                            }
                            dismiss()
                        }
                        Button("Modifier l’horaire « \(h.nom) »") { edition = h }
                    } footer: {
                        Text("Une pratique annulée peut être rétablie dans Plus › Horaires réguliers.")
                    }
                }
            }
            .navigationTitle("Horaire régulier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(item: $edition, onDismiss: { dismiss() }) { HoraireEditeur(original: $0) }
        }
        .presentationDetents([.medium, .large])
    }
}
