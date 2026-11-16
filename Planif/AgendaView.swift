import SwiftUI

struct CleId: Identifiable { let id: String }

struct AgendaView: View {
    @EnvironmentObject var store: Store
    enum Mode: String, CaseIterable { case semaine = "Semaine", jour = "Jour", liste = "Liste" }

    @AppStorage("agendaMode") private var modeBrut = Mode.semaine.rawValue
    @State private var date = D.today()
    @State private var cours: CleId?
    @State private var evenement: Evenement?
    @State private var nouvelEvenement = false
    @State private var choixDate = false
    @State private var jourCycle: CleId?

    private var mode: Mode { Mode(rawValue: modeBrut) ?? .semaine }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack {
                        Button { decaler(-1) } label: { Image(systemName: "chevron.left").padding(8) }
                        Spacer()
                        VStack(spacing: 4) {
                            Text(titre).font(.headline).multilineTextAlignment(.center)
                            if mode == .jour {
                                Button { jourCycle = CleId(id: date) } label: {
                                    Text(store.moteur.jourCycle(date).map { store.moteur.etiquetteJour($0) } ?? "Pas d’école")
                                        .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 3)
                                        .overlay(Capsule().stroke(Theme.vert, lineWidth: 1.5))
                                }
                            }
                        }
                        Spacer()
                        Button { decaler(1) } label: { Image(systemName: "chevron.right").padding(8) }
                    }
                    Picker("Affichage", selection: $modeBrut) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
                .background(Color.white)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) { contenu }
                        .padding(16)
                }
            }
            .background(Theme.fond)
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Aujourd’hui") { date = D.today() } }
                ToolbarItem(placement: .topBarTrailing) { Button { choixDate = true } label: { Image(systemName: "calendar") } }
                ToolbarItem(placement: .topBarTrailing) { Button { nouvelEvenement = true } label: { Image(systemName: "plus") } }
            }
            .sheet(item: $cours) { CoursSheet(cle: $0.id) }
            .sheet(item: $evenement) { EvenementEditeur(original: $0) }
            .sheet(isPresented: $nouvelEvenement) { EvenementEditeur(original: Evenement(titre: "", date: date)) }
            .sheet(isPresented: $choixDate) { ChoixDateSheet(date: $date) }
            .sheet(item: $jourCycle) { JourCycleSheet(date: $0.id) }
        }
    }

    private var titre: String {
        switch mode {
        case .semaine:
            let lun = D.monday(date), ven = D.add(lun, 4)
            return "Semaine du \(D.jm(lun)) au \(D.jm(ven))"
        case .jour: return D.long(date)
        case .liste: return "À venir"
        }
    }

    private func decaler(_ sens: Int) {
        let n = mode == .semaine ? 7 : mode == .jour ? 1 : 14
        date = D.add(date, sens * n)
    }

    private func ouvrir(_ x: ItemJour) {
        switch x.type {
        case .cours: cours = CleId(id: x.cle)
        case .evenement: evenement = x.evenement
        case .libre: break
        }
    }

    @ViewBuilder private var contenu: some View {
        let m = store.moteur
        switch mode {
        case .semaine:
            let lun = D.monday(date)
            ForEach(0..<5, id: \.self) { i in
                let x = D.add(lun, i)
                let its = m.items(x).filter { $0.type != .libre }
                HStack(alignment: .top, spacing: 10) {
                    Button { date = x; modeBrut = Mode.jour.rawValue } label: {
                        VStack(spacing: 1) {
                            Text(D.jourCourt[D.weekday(x)].capitalized + ".").font(.footnote.bold())
                            Text("\(D.cal.component(.day, from: D.date(x)))").font(.title2)
                            Text(m.jourCycle(x).map { "J\($0)" } ?? "—").font(.caption.bold()).opacity(0.8)
                        }
                        .frame(width: 58).padding(.vertical, 8)
                        .background(x == D.today() ? Theme.vert : Theme.tuile, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(x == D.today() ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    VStack(spacing: 6) {
                        if its.isEmpty {
                            Text(m.jourCycle(x) == nil ? "Pas d’école" : "Aucun cours")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.ligne, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                        ForEach(its) { it in
                            Button { ouvrir(it) } label: { LigneItem(item: it, moteur: m) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        case .jour:
            let its = m.items(date)
            if its.isEmpty {
                Text(m.jourCycle(date) == nil ? "Pas d’école ce jour-là." : "Aucune période. Remplis ta grille dans Horaire.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
            }
            ForEach(its) { it in
                HStack(alignment: .center, spacing: 8) {
                    Text(it.debut.isEmpty ? "Journée" : D.hm(it.debut).replacingOccurrences(of: "h", with: " h "))
                        .font(.subheadline.monospacedDigit()).frame(width: 62, alignment: .trailing)
                    Button { ouvrir(it) } label: { LigneItem(item: it, moteur: m, avecHeure: false) }.buttonStyle(.plain)
                }
            }
        case .liste:
            ForEach(0..<14, id: \.self) { i in
                let x = D.add(date, i)
                let its = m.items(x).filter { $0.type != .libre }
                if !its.isEmpty {
                    HStack {
                        Text(D.court(x)).font(.subheadline.bold())
                        Spacer()
                        Text(m.jourCycle(x).map { m.etiquetteJour($0) } ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                    ForEach(its) { it in
                        Button { ouvrir(it) } label: { LigneItem(item: it, moteur: m) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Fiche d'un cours

struct CoursSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let cle: String
    @State private var note = ""
    @State private var activite: Activite?

    var body: some View {
        let parts = cle.split(separator: "|").map(String.init)
        let date = parts.count == 3 ? parts[1] : D.today()
        let m = store.moteur
        let x = m.items(date).first { $0.cle == cle }
        NavigationStack {
            Form {
                if let x, let g = x.groupe {
                    Section {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.couleur(g.couleur).bande).frame(width: 6, height: 40)
                            VStack(alignment: .leading) {
                                Text(D.long(date)).bold()
                                Text("\(x.periode?.nom ?? "") · \(D.hm(x.debut))–\(D.hm(x.fin))" + (x.local.isEmpty ? "" : " · local \(x.local)"))
                                    .font(.subheadline)
                            }
                        }
                    }
                    Section("Planification") {
                        if x.annule {
                            Text(x.annuleParEvenement ? "Un événement annule les cours ce jour-là." : "Cours annulé : la planification est décalée au cours suivant.")
                        } else if let pt = m.texte(x.place), let p = x.place {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pt.titre).font(.headline)
                                if !pt.etape.isEmpty { Text("\(pt.etape) (étape \(pt.etapePos))") }
                                Text(pt.cours).font(.subheadline.bold())
                            }
                            Button("Voir l’activité") { activite = store.activite(p.a) }
                        } else {
                            Text("Rien de planifié").foregroundStyle(.secondary)
                        }
                        if !x.annuleParEvenement {
                            Button(x.annule ? "Rétablir le cours" : "Pas de cours (décaler la planif)") {
                                store.maj { d in
                                    if let i = d.annulations.firstIndex(of: cle) { d.annulations.remove(at: i) } else { d.annulations.append(cle) }
                                }
                            }
                        }
                    }
                    Section("Note") {
                        TextEditor(text: $note).frame(minHeight: 110)
                        Button("Enregistrer la note") {
                            let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.maj { d in d.notes[cle] = t.isEmpty ? nil : t }
                            dismiss()
                        }
                    }
                } else {
                    Text("Ce cours n’existe plus.")
                }
            }
            .navigationTitle(x?.groupe?.nom ?? "Cours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .onAppear { note = store.data.notes[cle] ?? "" }
            .sheet(item: $activite) { a in NavigationStack { ActiviteDetailView(activiteId: a.id) } }
        }
    }
}

struct ChoixDateSheet: View {
    @Binding var date: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: liaisonDate($date), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Aller à une date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Changer le statut d'une date : journée sans école, ou jour de cycle forcé.
struct JourCycleSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let date: String

    var body: some View {
        let m = store.moteur
        let force = store.data.config.cycleMap[date]
        let sansEcole = m.sansEcole.first { date >= $0.date && date <= ($0.dateFin.isEmpty ? $0.date : $0.dateFin) }
        NavigationStack {
            Form {
                Section {
                    Text(m.jourCycle(date).map { m.etiquetteJour($0) } ?? "Pas d’école").font(.headline)
                    if let s = sansEcole { Text(s.titre + " — " + s.type.label).foregroundStyle(.secondary) }
                }
                if let s = sansEcole {
                    Button("Ce n’est pas un jour sans école (retirer)", role: .destructive) {
                        store.maj { d in d.evenements.removeAll { $0.id == s.id } }
                        dismiss()
                    }
                } else {
                    Section {
                        Button("Journée pédagogique") { marquer(.pedago) }
                        Button("Congé") { marquer(.conge) }
                    } header: { Text("Pas d’école ce jour-là?") } footer: {
                        Text("Le cycle reprendra le jour d’école suivant, sans sauter de numéro.")
                    }
                }
                Section {
                    ForEach(1...m.L, id: \.self) { j in
                        Button {
                            store.maj { d in d.config.cycleMap[date] = j }
                            dismiss()
                        } label: {
                            HStack { Text(m.etiquetteJour(j)); Spacer(); if force == j { Image(systemName: "checkmark") } }
                        }
                    }
                    Button {
                        store.maj { d in d.config.cycleMap[date] = nil }
                        dismiss()
                    } label: {
                        HStack { Text("Automatique"); Spacer(); if force == nil { Image(systemName: "checkmark") } }
                    }
                } header: { Text("Forcer le jour de cycle") } footer: {
                    Text("Pour corriger une date. Les jours suivants continuent à partir de ce numéro.")
                }
            }
            .navigationTitle(D.long(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func marquer(_ t: TypeEvenement) {
        store.maj { d in
            d.config.cycleMap[date] = nil
            _ = store.ajouterSansEcole(t.label, date: date, fin: "", type: t, dans: &d)
        }
        dismiss()
    }
}
