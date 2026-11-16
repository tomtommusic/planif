import SwiftUI

/// Grille du cycle : on touche un groupe puis les cases, ou on glisse un groupe dans une case.
struct GrilleView: View {
    @EnvironmentObject var store: Store
    @State private var choix: String?          // id de groupe ou "__effacer"
    @State private var caseChoisie: CleId?
    @State private var parametres = false
    @State private var nouveauGroupe = false

    private let largeur: CGFloat = 96
    private let hauteur: CGFloat = 64

    var body: some View {
        let m = store.moteur
        VStack(alignment: .leading, spacing: 0) {
            palette
            if store.data.groupes.isEmpty {
                ContentUnavailableView("Aucun groupe", systemImage: "person.2", description: Text("Ajoute d’abord tes groupes."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                        GridRow {
                            Color.clear.frame(width: 86, height: 34)
                            ForEach(1...m.L, id: \.self) { j in
                                Text(m.etiquetteJour(j)).font(.caption.bold())
                                    .frame(width: largeur, height: 34).background(Theme.tuile)
                            }
                        }
                        ForEach(m.periodesTriees) { p in
                            GridRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.nom).font(.caption.bold()).lineLimit(2)
                                    Text("\(D.hm(p.debut))–\(D.hm(p.fin))").font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.leading, 6)
                                .frame(width: 86, height: hauteur, alignment: .leading)
                                .background(Theme.tuile.opacity(0.6))
                                ForEach(1...m.L, id: \.self) { j in caseVue(j: j, p: p) }
                            }
                        }
                    }
                    .background(Theme.ligne)
                    .padding(12)
                }
                Text("\(store.data.cellules.count) périodes placées sur \(m.L * store.data.periodes.count).")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .background(Theme.fond)
        .navigationTitle("Horaire")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { parametres = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(item: $caseChoisie) { CaseSheet(cle: $0.id) }
        .sheet(isPresented: $parametres) { ParametresGrilleSheet() }
        .sheet(isPresented: $nouveauGroupe) { GroupeEditeur(original: nil) }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Touche un groupe, puis les cases où il va. Tu peux aussi le glisser. Garde le doigt sur une case remplie pour la déplacer.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.data.groupes) { g in
                        let c = Theme.couleur(g.couleur)
                        Text(g.nom).font(.subheadline.bold())
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(c.fond, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(c.bande).frame(width: 7) }
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(choix == g.id ? Color.primary : c.bande, lineWidth: choix == g.id ? 3 : 1.5))
                            .onTapGesture { choix = choix == g.id ? nil : g.id }
                            .draggable(g.id)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(g.nom + (choix == g.id ? ", choisi" : ""))
                    }
                    Button { choix = choix == "__effacer" ? nil : "__effacer" } label: {
                        Label("Effacer", systemImage: "eraser")
                    }
                    .buttonStyle(.bordered)
                    .tint(choix == "__effacer" ? Color.red : Color.primary)
                    Button { nouveauGroupe = true } label: { Image(systemName: "plus") }.buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            }
            if let c = choix {
                HStack {
                    Text(c == "__effacer" ? "Effacer : touche les cases à vider." : "\(store.groupe(c)?.nom ?? "") choisi : touche les cases où il va.")
                        .font(.footnote.bold())
                    Spacer()
                    Button("Terminé") { choix = nil }.buttonStyle(.bordered).tint(.white)
                }
                .padding(10)
                .background(Theme.vert, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(Theme.fond)
    }

    private func caseVue(j: Int, p: Periode) -> some View {
        let cle = "\(j)|\(p.id)"
        let cell = store.data.cellules[cle]
        let g = cell.flatMap { store.groupe($0.g) }
        return ZStack(alignment: .topLeading) {
            if let g {
                let c = Theme.couleur(g.couleur)
                c.fond
                HStack(spacing: 0) {
                    c.bande.frame(width: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.nom).font(.caption.bold()).lineLimit(2)
                        let local = (cell?.local.isEmpty ?? true) ? g.local : (cell?.local ?? "")
                        if !local.isEmpty { Text(local).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .padding(5)
                    Spacer(minLength: 0)
                }
            } else {
                Color.white
                Image(systemName: "plus").foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: largeur, height: hauteur)
        .contentShape(Rectangle())
        .onTapGesture { toucher(cle) }
        .deplacable(g != nil ? "case:" + cle : nil)
        .dropDestination(for: String.self) { items, _ in
            guard let v = items.first else { return false }
            deposer(v, sur: cle)
            return true
        }
        .accessibilityLabel("\(store.moteur.etiquetteJour(j)), \(p.nom) : \(g?.nom ?? "vide")")
        .accessibilityAddTraits(.isButton)
    }

    private func toucher(_ cle: String) {
        if choix == "__effacer" {
            store.maj { d in d.cellules[cle] = nil }
        } else if let c = choix {
            store.maj { d in d.cellules[cle] = Cellule(g: c) }
        } else {
            caseChoisie = CleId(id: cle)
        }
    }

    private func deposer(_ v: String, sur cle: String) {
        store.maj { d in
            if v.hasPrefix("case:") {
                let source = String(v.dropFirst(5))
                guard source != cle else { return }
                let tmp = d.cellules[cle]
                d.cellules[cle] = d.cellules[source]
                d.cellules[source] = tmp
            } else if d.groupes.contains(where: { $0.id == v }) {
                d.cellules[cle] = Cellule(g: v)
            }
        }
    }
}

struct CaseSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let cle: String
    @State private var local = ""

    var body: some View {
        let parts = cle.split(separator: "|").map(String.init)
        let j = Int(parts.first ?? "") ?? 1
        let p = store.data.periodes.first { $0.id == parts.last }
        let actuel = store.data.cellules[cle]?.g
        NavigationStack {
            Form {
                Section("Groupe") {
                    ForEach(store.data.groupes) { g in
                        Button {
                            store.maj { d in d.cellules[cle] = Cellule(g: g.id, local: local) }
                            dismiss()
                        } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.couleur(g.couleur).bande).frame(width: 6, height: 24)
                                Text(g.nom).foregroundStyle(.primary)
                                Spacer()
                                if actuel == g.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if actuel != nil {
                        Button("Libérer la case", role: .destructive) {
                            store.maj { d in d.cellules[cle] = nil }
                            dismiss()
                        }
                    }
                }
                Section("Local (si différent du local habituel)") {
                    TextField("Local", text: $local)
                    if actuel != nil {
                        Button("Enregistrer le local") {
                            store.maj { d in d.cellules[cle]?.local = local }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("\(store.moteur.etiquetteJour(j)) · \(p?.nom ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onAppear { local = store.data.cellules[cle]?.local ?? "" }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ParametresGrilleSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var config = Config(debut: "", fin: "", refDate: "")
    @State private var periodes: [Periode] = []
    @State private var choix = 9

    var body: some View {
        NavigationStack {
            Form {
                ReglagesCycle(config: $config, choix: $choix)
                ReglagesPeriodes(periodes: $periodes)
                Section {
                    Text("Retirer une période ou réduire le nombre de jours vide les cases concernées.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Paramètres de la grille")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.maj { d in
                            d.config.cycleLen = config.cycleLen
                            d.config.hebdo = config.hebdo
                            d.periodes = periodes
                            nettoyerGrille(&d)
                        }
                        dismiss()
                    }
                    .disabled(periodes.isEmpty)
                }
            }
            .onAppear {
                config = store.data.config
                periodes = store.data.periodes
                choix = [5, 9, 10].contains(config.cycleLen) ? config.cycleLen : 0
            }
        }
    }
}
