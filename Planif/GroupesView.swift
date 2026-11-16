import SwiftUI

struct GroupesView: View {
    @EnvironmentObject var store: Store
    @State private var nouveau = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.data.groupes.isEmpty {
                        ContentUnavailableView("Aucun groupe", systemImage: "person.2", description: Text("Touche + pour ajouter un groupe."))
                    }
                    ForEach(store.data.groupes) { g in
                        NavigationLink { GroupeDetailView(groupeId: g.id) } label: { CarteGroupe(groupe: g) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.fond)
            .navigationTitle("Groupes de classe")
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { nouveau = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $nouveau) { GroupeEditeur(original: nil) }
        }
    }
}

struct CarteGroupe: View {
    @EnvironmentObject var store: Store
    let groupe: Groupe

    var body: some View {
        let c = Theme.couleur(groupe.couleur)
        let m = store.moteur
        let t = D.today(), h = D.nowHM()
        let prochain = (m.plagesParGroupe[groupe.id] ?? []).first { $0.date > t || ($0.date == t && $0.fin > h) }
        HStack(spacing: 14) {
            Image(systemName: groupe.icone).frame(width: 44, height: 44)
                .background(Color.white, in: Circle()).overlay(Circle().stroke(Theme.ligne))
            VStack(alignment: .leading, spacing: 2) {
                Text(groupe.nom).font(.title3.bold())
                Text("\(groupe.eleves.count) élève\(groupe.eleves.count > 1 ? "s" : "")").font(.subheadline).foregroundStyle(.secondary)
                if let p = prochain {
                    let pt = m.texte(m.plan.places[Moteur.cle(groupe.id, p.date, p.pid)])
                    Text("Prochain cours : \(D.court(p.date)) \(D.hm(p.debut))" + (pt.map { " — " + $0.titre } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(14)
        .background(LinearGradient(colors: [c.fond, .white], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12).fill(c.bande).frame(width: 7) }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ligne))
    }
}

struct GroupeDetailView: View {
    @EnvironmentObject var store: Store
    let groupeId: String
    @State private var onglet = 0
    @State private var edition = false
    @State private var nouvelEleve = ""
    @State private var coller = false
    @State private var cours: CleId?

    var body: some View {
        if let g = store.groupe(groupeId) {
            List {
                Picker("", selection: $onglet) {
                    Text("Planif").tag(0)
                    Text("Élèves (\(g.eleves.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if onglet == 0 { planif(g) } else { eleves(g) }
            }
            .navigationTitle(g.nom)
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { edition = true } label: { Image(systemName: "pencil") } } }
            .sheet(isPresented: $edition) { GroupeEditeur(original: g) }
            .sheet(isPresented: $coller) { CollerListeSheet(groupeId: g.id) }
            .sheet(item: $cours) { CoursSheet(cle: $0.id) }
        } else {
            ContentUnavailableView("Groupe supprimé", systemImage: "person.2.slash")
        }
    }

    @ViewBuilder private func planif(_ g: Groupe) -> some View {
        let m = store.moteur
        let t = D.today()
        let plages = m.plagesParGroupe[g.id] ?? []
        let passees = Array(plages.filter { $0.date < t }.suffix(3))
        let futures = Array(plages.filter { $0.date >= t }.prefix(25))
        if plages.isEmpty {
            Text("Ce groupe n’est pas encore dans la grille. Place-le dans Horaire.").foregroundStyle(.secondary)
        }
        Section("\(plages.count) périodes cette année") {
            ForEach(passees + futures, id: \.self) { p in
                let k = Moteur.cle(g.id, p.date, p.pid)
                let annule = store.data.annulations.contains(k) || m.coursAnnulesLe(p.date)
                Button { cours = CleId(id: k) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(D.court(p.date)) · \(m.periodesTriees.first { $0.id == p.pid }?.nom ?? "") \(D.hm(p.debut))")
                            .font(.caption.bold()).foregroundStyle(p.date < t ? Color.secondary : Color.primary)
                        if annule {
                            Text("Annulé").strikethrough()
                        } else if let pt = m.texte(m.plan.places[k]) {
                            Text(pt.titre + (pt.etape.isEmpty ? "" : " — " + pt.etape)).foregroundStyle(.primary)
                            Text(pt.cours).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Rien de planifié").foregroundStyle(.secondary)
                        }
                        if let n = store.data.notes[k] { Text("✎ " + n).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func eleves(_ g: Groupe) -> some View {
        Section {
            HStack {
                TextField("Nom de l’élève", text: $nouvelEleve).onSubmit { ajouter(g) }
                Button("Ajouter") { ajouter(g) }.disabled(nouvelEleve.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button { coller = true } label: { Label("Coller une liste", systemImage: "doc.on.clipboard") }
            if g.eleves.count > 1 {
                Button { store.maj { d in if let i = d.groupes.firstIndex(where: { $0.id == g.id }) { d.groupes[i].eleves.sort { $0.nom.localizedCompare($1.nom) == .orderedAscending } } } } label: {
                    Label("Trier A → Z", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        Section {
            ForEach(Array(g.eleves.enumerated()), id: \.element.id) { i, e in
                HStack { Text("\(i + 1)").foregroundStyle(.secondary).frame(width: 26, alignment: .leading); Text(e.nom) }
            }
            .onDelete { idx in
                store.maj { d in if let i = d.groupes.firstIndex(where: { $0.id == g.id }) { d.groupes[i].eleves.remove(atOffsets: idx) } }
            }
        }
    }

    private func ajouter(_ g: Groupe) {
        let n = normaliserNom(nouvelEleve)
        guard !n.isEmpty else { return }
        store.maj { d in if let i = d.groupes.firstIndex(where: { $0.id == g.id }) { d.groupes[i].eleves.append(Eleve(nom: n)) } }
        nouvelEleve = ""
    }
}

/// « Nom, Prénom » devient « Prénom Nom ».
func normaliserNom(_ s: String) -> String {
    let t = s.replacingOccurrences(of: "\t", with: " ").split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
    let parts = t.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    if parts.count == 2, !parts[1].isEmpty { return parts[1] + " " + parts[0] }
    return t
}

struct CollerListeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let groupeId: String
    @State private var texte = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $texte).frame(minHeight: 220)
                } footer: {
                    Text("Un élève par ligne. « Nom, Prénom » devient « Prénom Nom ».")
                }
            }
            .navigationTitle("Coller une liste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let noms = texte.split(separator: "\n").map { normaliserNom(String($0)) }.filter { !$0.isEmpty }
                        store.maj { d in
                            guard let i = d.groupes.firstIndex(where: { $0.id == groupeId }) else { return }
                            var deja = Set(d.groupes[i].eleves.map { $0.nom.lowercased() })
                            for n in noms where !deja.contains(n.lowercased()) {
                                d.groupes[i].eleves.append(Eleve(nom: n))
                                deja.insert(n.lowercased())
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GroupeEditeur: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: Groupe?
    @State private var g = Groupe(nom: "")
    @State private var pret = false
    @State private var confirmer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex. Groupe A (3e))", text: $g.nom)
                    TextField("Local habituel", text: $g.local)
                }
                Section("Couleur") {
                    ForEach(Theme.palette) { c in
                        Button { g.couleur = c.id } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 3).fill(c.bande).frame(width: 8, height: 26)
                                Text(c.nom).foregroundStyle(.primary)
                                Spacer()
                                if g.couleur == c.id { Image(systemName: "checkmark").bold() }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowBackground(c.fond)
                    }
                }
                Section("Icône") {
                    ForEach(Theme.icones) { ic in
                        Button { g.icone = ic.id } label: {
                            HStack { Image(systemName: ic.id).frame(width: 28); Text(ic.nom).foregroundStyle(.primary); Spacer(); if g.icone == ic.id { Image(systemName: "checkmark").bold() } }
                        }
                    }
                }
                if original != nil {
                    Section {
                        Button("Supprimer le groupe", role: .destructive) { confirmer = true }
                    } footer: {
                        Text("Le groupe est retiré de la grille et des activités, et ses élèves sont effacés.")
                    }
                }
            }
            .navigationTitle(original == nil ? "Nouveau groupe" : "Modifier le groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let nom = g.nom.trimmingCharacters(in: .whitespaces)
                        store.maj { d in
                            var x = g; x.nom = nom
                            if let i = d.groupes.firstIndex(where: { $0.id == x.id }) { d.groupes[i] = x } else { d.groupes.append(x) }
                        }
                        dismiss()
                    }
                    .disabled(g.nom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Supprimer ce groupe?", isPresented: $confirmer, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    let id = g.id
                    store.maj { d in
                        d.groupes.removeAll { $0.id == id }
                        d.cellules = d.cellules.filter { $0.value.g != id }
                        for i in d.activites.indices { d.activites[i].groupes.removeAll { $0 == id } }
                    }
                    dismiss()
                }
            }
            .onAppear {
                guard !pret else { return }
                pret = true
                if let o = original { g = o } else {
                    let pris = Set(store.data.groupes.map { $0.couleur })
                    g.couleur = Theme.palette.first { !pris.contains($0.id) }?.id ?? "sauge"
                }
            }
        }
    }
}
