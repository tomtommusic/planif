import SwiftUI

// MARK: - Calendrier scolaire : un mois à la fois, avec le jour de cycle, les pédagos, les congés et les événements

struct CalendrierView: View {
    @EnvironmentObject var store: Store
    @State private var mois = D.premierDuMois(D.today())
    @State private var choisi: CleId?

    private let colonnes = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            let m = store.moteur
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button { mois = D.moisDecale(mois, -1) } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Mois précédent")
                        Spacer()
                        Text(D.mois(mois)).font(.title2.bold())
                        Spacer()
                        Button { mois = D.moisDecale(mois, 1) } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Mois suivant")
                    }
                    .foregroundStyle(Theme.vert)

                    LazyVGrid(columns: colonnes, spacing: 4) {
                        ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { i in
                            Text(["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"][i])
                                .font(.caption2.bold()).foregroundStyle(.secondary)
                        }
                        ForEach(cases, id: \.self) { date in
                            if date.isEmpty {
                                Color.clear.frame(height: 58)
                            } else {
                                Button { choisi = CleId(id: date) } label: { caseJour(date, m: m) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    legende

                    NavigationLink { ImportView() } label: {
                        Label("Importer un document (calendrier, comités, événements)", systemImage: "doc.viewfinder")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(Theme.vert)

                    let marquants = joursMarquants(m)
                    if !marquants.isEmpty {
                        Text("CE MOIS-CI").font(.caption.weight(.heavy)).foregroundStyle(.secondary).padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(marquants.enumerated()), id: \.offset) { i, x in
                                Button { choisi = CleId(id: x.date) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(D.court(x.date)).font(.subheadline.bold()).frame(width: 96, alignment: .leading)
                                        Label(x.titre, systemImage: x.icone).font(.subheadline)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if i < marquants.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(16)
            }
            .background(Theme.fond)
            .navigationTitle("Calendrier scolaire")
            .navigationBarTitleDisplayMode(.inline)
            .barreVerte()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ImportView() } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                        .accessibilityLabel("Importer un document")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aujourd’hui") { mois = D.premierDuMois(D.today()) }
                }
            }
            .sheet(item: $choisi) { JourDetailSheet(date: $0.id) }
        }
    }

    /// Cases du mois, lundi en premier ; "" = case vide.
    private var cases: [String] {
        let premier = mois
        let decalage = (D.weekday(premier) + 6) % 7
        var out = Array(repeating: "", count: decalage)
        var x = premier
        while D.premierDuMois(x) == premier {
            out.append(x)
            x = D.add(x, 1)
        }
        while out.count % 7 != 0 { out.append("") }
        return out
    }

    private enum Genre { case cycle(Int), pedago, conge, sansEcole, horsAnnee, finDeSemaine }

    private func genre(_ date: String, _ m: Moteur) -> Genre {
        let wd = D.weekday(date)
        if let cd = m.jourCycle(date) { return .cycle(cd) }
        if wd == 0 || wd == 6 { return .finDeSemaine }
        let c = store.data.config
        if date < c.debut || date > c.fin { return .horsAnnee }
        if let e = m.evenements(date).first(where: { $0.type.sansEcole }) { return e.type == .pedago ? .pedago : .conge }
        return .sansEcole
    }

    private func caseJour(_ date: String, m: Moteur) -> some View {
        let g = genre(date, m)
        let auj = date == D.today()
        let evts = m.evenements(date).filter { !$0.type.sansEcole && $0.horaireId == nil }
        let etiquette: String
        let fond: Color
        switch g {
        case .cycle(let n): etiquette = "J\(n)"; fond = Theme.carte
        case .pedago: etiquette = "Péd."; fond = Color(hex: "dbe8f4")
        case .conge: etiquette = "Congé"; fond = Color(hex: "e2ecd6")
        case .sansEcole: etiquette = "Libre"; fond = Color(hex: "e7e8e4")
        case .horsAnnee, .finDeSemaine: etiquette = ""; fond = .clear
        }
        return VStack(spacing: 2) {
            Text(String(Int(date.suffix(2)) ?? 0))
                .font(.subheadline.weight(auj ? .heavy : .semibold))
                .foregroundStyle(etiquette.isEmpty ? Color.secondary : Color.primary)
            Text(etiquette).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(evts.isEmpty ? " " : (evts.count == 1 ? "• 1" : "• \(evts.count)"))
                .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.lavandeBande)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(fond, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.vert, lineWidth: auj ? 2.5 : 0))
        .accessibilityElement(children: .combine)
    }

    private var legende: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("J3 = jour 3 du cycle · Péd. = journée pédagogique · Congé = pas d’école · • 2 = deux événements. Aujourd’hui est encadré.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private struct Marquant { let date: String; let titre: String; let icone: String }

    private func joursMarquants(_ m: Moteur) -> [Marquant] {
        cases.filter { !$0.isEmpty }.flatMap { date -> [Marquant] in
            m.evenements(date).filter { $0.horaireId == nil && ($0.date == date || $0.type.sansEcole == false) }
                .map { Marquant(date: date, titre: $0.titre, icone: $0.type.symbole) }
        }
    }
}

/// Détail d'une journée : jour de cycle, événements et cours.
struct JourDetailSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let date: String
    @State private var cours: CleId?
    @State private var jourCycle: CleId?

    var body: some View {
        let m = store.moteur
        let items = m.items(date)
        NavigationStack {
            List {
                Section {
                    Button { jourCycle = CleId(id: date) } label: {
                        HStack {
                            Text(m.jourCycle(date).map { m.etiquetteJour($0) } ?? "Pas d’école").bold()
                            Spacer()
                            Text("Modifier").font(.subheadline)
                        }
                    }
                }
                if items.isEmpty {
                    Text("Rien ce jour-là.").foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(items) { x in
                            if x.type == .cours {
                                Button { cours = CleId(id: x.cle) } label: { LigneItem(item: x, moteur: m) }.buttonStyle(.plain)
                            } else {
                                LigneItem(item: x, moteur: m)
                            }
                        }
                    }
                }
            }
            .navigationTitle(D.long(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(item: $cours) { CoursSheet(cle: $0.id) }
            .sheet(item: $jourCycle) { JourCycleSheet(date: $0.id) }
        }
        .presentationDetents([.medium, .large])
    }
}
