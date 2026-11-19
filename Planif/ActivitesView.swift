import SwiftUI

struct ActivitesView: View {
    @EnvironmentObject var store: Store
    @State private var nouvelle = false
    @State private var filtre = ""
    var dansPile = true

    var body: some View {
        if dansPile { NavigationStack { contenu } } else { contenu }
    }

    @ViewBuilder private var contenu: some View {
        Group {
            let m = store.moteur
            let liste = store.data.activites.filter { filtre.isEmpty || $0.groupes.contains(filtre) }
            List {
                Section {
                    Text("Chaque activité se place dans les prochaines périodes des groupes choisis, dans l’ordre de la liste. Annule un cours ou change l’ordre : tout se décale.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !store.data.groupes.isEmpty {
                        Picker("Groupe", selection: $filtre) {
                            Text("Tous les groupes").tag("")
                            ForEach(store.data.groupes) { Text($0.nom).tag($0.id) }
                        }
                    }
                }
                if liste.isEmpty {
                    ContentUnavailableView("Aucune activité", systemImage: "square.stack.3d.up", description: Text("Touche + pour créer une activité."))
                }
                ForEach(liste) { a in
                    NavigationLink { ActiviteDetailView(activiteId: a.id) } label: { LigneActivite(a: a, moteur: m) }
                }
                .onMove { from, to in
                    guard filtre.isEmpty else { return }
                    store.maj { d in d.activites.move(fromOffsets: from, toOffset: to) }
                }
            }
            .navigationTitle("Activités")
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { if filtre.isEmpty && store.data.activites.count > 1 { EditButton() } }
                ToolbarItem(placement: .topBarTrailing) { Button { nouvelle = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $nouvelle) { ActiviteEditeur(original: nil, groupeInitial: filtre.isEmpty ? nil : filtre) }
        }
    }
}

struct LigneActivite: View {
    @EnvironmentObject var store: Store
    let a: Activite
    let moteur: Moteur

    var body: some View {
        let s = moteur.stats(a)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: a.icone).font(.title2).frame(width: 48, height: 48)
                .background(Color(hex: "f6e4cb"), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(a.titre).font(.headline)
                Text(a.groupes.compactMap { store.groupe($0)?.nom }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                Text("\(moteur.sequence(a).count) périodes" + (a.etapes.isEmpty ? "" : " · \(a.etapes.count) étapes")
                     + (s.premier.map { " · \(D.jm($0)) → \(D.jm(s.dernier ?? $0))" } ?? ""))
                    .font(.caption)
                if s.total > 0 { ProgressView(value: Double(s.faites), total: Double(s.total)).tint(Theme.vert3) }
                if s.manquantes > 0 { Text("⚠︎ \(s.manquantes) période(s) ne rentrent pas").font(.caption.bold()) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActiviteDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let activiteId: String
    @State private var onglet = 0
    @State private var edition = false

    var body: some View {
        if let a = store.activite(activiteId) {
            let m = store.moteur
            let s = m.stats(a)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: a.icone).font(.system(size: 30)).frame(width: 64, height: 64)
                            .background(Color(hex: "f6e4cb"), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(a.titre).font(.title2.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(a.groupes, id: \.self) { EtiquetteGroupe(groupe: store.groupe($0)) } }
                            }
                        }
                    }
                    Picker("", selection: $onglet) {
                        Text("Détails").tag(0)
                        Text("Planification").tag(1)
                        Text("Ressources").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch onglet {
                    case 0: details(a, m, s)
                    case 1: planification(a, m)
                    default: ressources(a)
                    }
                }
                .padding(16)
            }
            .background(Theme.fond)
            .navigationTitle("Activité")
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { edition = true } label: { Image(systemName: "pencil") } }
            }
            .sheet(isPresented: $edition) { ActiviteEditeur(original: a, groupeInitial: nil) }
        } else {
            ContentUnavailableView("Activité supprimée", systemImage: "square.stack.3d.up.slash")
        }
    }

    @ViewBuilder private func details(_ a: Activite, _ m: Moteur, _ s: Moteur.Stats) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
            VStack(alignment: .leading, spacing: 2) {
                if let p = s.premier, let d = s.dernier {
                    Text("Du \(D.court(p).lowercased()) au \(D.court(d).lowercased())")
                    Text("(\(s.jours) jour\(s.jours > 1 ? "s" : "") de classe · \(m.sequence(a).count) périodes par groupe)").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(a.groupes.isEmpty ? "Choisis des groupes pour placer l’activité." : "Pas encore placée (groupe absent de la grille?).").foregroundStyle(.secondary)
                }
            }
        }.carte()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "target")
            VStack(alignment: .leading, spacing: 2) {
                Text("Objectif").font(.headline)
                Text(a.objectif.isEmpty ? "Aucun objectif écrit." : a.objectif).foregroundStyle(a.objectif.isEmpty ? Color.secondary : Color.primary)
            }
        }.carte()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.square")
            VStack(alignment: .leading, spacing: 6) {
                Text("Étapes").font(.headline)
                if a.etapes.isEmpty { Text("Pas d’étapes : \(m.sequence(a).count) période(s).").foregroundStyle(.secondary) }
                ForEach(a.etapes) { e in
                    Button {
                        store.maj { d in
                            if let i = d.activites.firstIndex(where: { $0.id == a.id }), let j = d.activites[i].etapes.firstIndex(where: { $0.id == e.id }) {
                                d.activites[i].etapes[j].fait.toggle()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: e.fait ? "checkmark.square.fill" : "square").foregroundStyle(Theme.vert2).font(.title3)
                            Text(e.titre).strikethrough(e.fait).foregroundStyle(e.fait ? Color.secondary : Color.primary)
                            Text("(\(e.periodes) pér.)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }.carte()
        if s.total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Progression").font(.headline); Spacer(); Text("\(s.faites) / \(s.total) périodes") }
                ProgressView(value: Double(s.faites), total: Double(s.total)).tint(Theme.vert3)
                if s.manquantes > 0 { Text("⚠︎ \(s.manquantes) période(s) ne rentrent pas avant la fin de l’année").font(.footnote.bold()) }
            }.carte()
        }
    }

    @ViewBuilder private func planification(_ a: Activite, _ m: Moteur) -> some View {
        let t = D.today()
        let etapes = a.etapes.filter { $0.periodes > 0 }
        ForEach(a.groupes, id: \.self) { gid in
            let r = m.plan.portees[a.id + "|" + gid]
            VStack(alignment: .leading, spacing: 6) {
                HStack { EtiquetteGroupe(groupe: store.groupe(gid)); Spacer(); Text("\(r?.placees ?? 0)/\(r?.total ?? 0)").font(.caption).foregroundStyle(.secondary) }
                if let r, !r.slots.isEmpty {
                    ForEach(Array(r.slots.enumerated()), id: \.offset) { i, p in
                        let pl = m.plan.places[Moteur.cle(gid, p.date, p.pid)]
                        HStack(alignment: .top) {
                            Image(systemName: p.date < t ? "circle.fill" : "circle").font(.caption2).foregroundStyle(Theme.vert3).padding(.top, 4)
                            VStack(alignment: .leading) {
                                Text("\(D.court(p.date)) · \(D.hm(p.debut))").font(.subheadline.bold())
                                if let pl, pl.si >= 0, pl.si < etapes.count {
                                    Text("\(etapes[pl.si].titre) (\(pl.sk + 1)/\(pl.sn))").font(.caption)
                                } else {
                                    Text("Période \(i + 1)").font(.caption)
                                }
                            }
                            .foregroundStyle(p.date < t ? Color.secondary : Color.primary)
                        }
                    }
                    if r.placees < r.total { Text("⚠︎ \(r.total - r.placees) période(s) ne rentrent pas.").font(.footnote.bold()) }
                } else {
                    Text("Pas encore placé (groupe absent de la grille ou plus de périodes cette année).").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .carte()
        }
    }

    @ViewBuilder private func ressources(_ a: Activite) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link")
            VStack(alignment: .leading, spacing: 4) {
                Text("Ressources").font(.headline)
                if a.ressources.isEmpty {
                    Text("Liens, documents, matériel à prévoir…").foregroundStyle(.secondary)
                } else {
                    Text(LocalizedStringKey(a.ressources)).textSelection(.enabled)
                }
            }
        }.carte()
    }
}

struct ActiviteEditeur: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: Activite?
    let groupeInitial: String?
    @State private var a = Activite(titre: "")
    @State private var pret = false
    @State private var confirmer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre (ex. Les écosystèmes)", text: $a.titre)
                    TextField("Objectif", text: $a.objectif, axis: .vertical).lineLimit(2...5)
                }
                Section("Groupes concernés") {
                    if store.data.groupes.isEmpty { Text("Aucun groupe.").foregroundStyle(.secondary) }
                    ForEach(store.data.groupes) { g in
                        Toggle(g.nom, isOn: Binding(
                            get: { a.groupes.contains(g.id) },
                            set: { on in if on { a.groupes.append(g.id) } else { a.groupes.removeAll { $0 == g.id } } }
                        ))
                    }
                }
                Section {
                    DatePicker("Commencer à partir du", selection: liaisonDate($a.debut), displayedComponents: .date)
                }
                Section {
                    ForEach($a.etapes) { $e in
                        HStack {
                            TextField("Étape", text: $e.titre)
                            Stepper("\(e.periodes) pér.", value: $e.periodes, in: 1...60).fixedSize()
                        }
                    }
                    .onDelete { a.etapes.remove(atOffsets: $0) }
                    .onMove { a.etapes.move(fromOffsets: $0, toOffset: $1) }
                    Button { a.etapes.append(Etape(titre: "")) } label: { Label("Ajouter une étape", systemImage: "plus") }
                    if a.etapes.isEmpty {
                        Stepper("Nombre de périodes : \(a.nbPeriodes)", value: $a.nbPeriodes, in: 1...200)
                    } else {
                        Text("Total : \(a.etapes.reduce(0) { $0 + $1.periodes }) périodes").bold()
                    }
                } header: { Text("Étapes") } footer: {
                    Text("Chaque étape et son nombre de périodes. Sans étape, indique seulement le total.")
                }
                Section("Ressources (liens, matériel)") {
                    TextField("https://…", text: $a.ressources, axis: .vertical).lineLimit(2...6)
                }
                Section("Icône") {
                    Picker("Icône", selection: $a.icone) {
                        ForEach(Theme.icones) { Label($0.nom, systemImage: $0.id).tag($0.id) }
                    }
                }
                if original != nil {
                    Section { Button("Supprimer l’activité", role: .destructive) { confirmer = true } }
                }
            }
            .navigationTitle(original == nil ? "Nouvelle activité" : "Modifier l’activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var x = a
                        x.titre = x.titre.trimmingCharacters(in: .whitespaces)
                        for i in x.etapes.indices where x.etapes[i].titre.trimmingCharacters(in: .whitespaces).isEmpty {
                            x.etapes[i].titre = "Étape \(i + 1)"
                        }
                        if !x.etapes.isEmpty { x.nbPeriodes = x.etapes.reduce(0) { $0 + $1.periodes } }
                        store.maj { d in
                            if let i = d.activites.firstIndex(where: { $0.id == x.id }) { d.activites[i] = x } else { d.activites.append(x) }
                        }
                        dismiss()
                    }
                    .disabled(a.titre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Supprimer cette activité?", isPresented: $confirmer, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    let id = a.id
                    store.maj { d in d.activites.removeAll { $0.id == id } }
                    dismiss()
                }
            }
            .onAppear {
                guard !pret else { return }
                pret = true
                if let o = original { a = o } else {
                    a.debut = D.today()
                    if let g = groupeInitial { a.groupes = [g] }
                }
            }
        }
    }
}
