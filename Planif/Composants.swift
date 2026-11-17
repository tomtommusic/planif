import SwiftUI

// MARK: - Liaisons utiles pour les champs date / heure stockés en texte

func liaisonDate(_ s: Binding<String>) -> Binding<Date> {
    Binding(get: { D.date(s.wrappedValue.isEmpty ? D.today() : s.wrappedValue) },
            set: { s.wrappedValue = D.iso($0) })
}

func liaisonHeure(_ s: Binding<String>, defaut: String = "08:00") -> Binding<Date> {
    Binding(get: { D.dateTime(D.today(), s.wrappedValue.isEmpty ? defaut : s.wrappedValue) },
            set: { s.wrappedValue = D.hhmm($0) })
}

// MARK: - Barre de navigation verte

extension View {
    func barreVerte() -> some View {
        self.toolbarBackground(Theme.vert, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder func deplacable(_ texte: String?) -> some View {
        if let texte { self.draggable(texte) } else { self }
    }

    func carte() -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ligne))
    }
}

// MARK: - Étiquettes de groupe

struct EtiquetteGroupe: View {
    let groupe: Groupe?
    var body: some View {
        let c = Theme.couleur(groupe?.couleur)
        Text(groupe?.nom ?? "?")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(c.fond, in: Capsule())
            .overlay(Capsule().stroke(c.bande, lineWidth: 1.5))
    }
}

// MARK: - Ligne d'agenda (cours, période libre ou événement)

struct LigneItem: View {
    let item: ItemJour
    let moteur: Moteur
    var avecHeure = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icone).frame(width: 24).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(titre).font(.subheadline.weight(.bold))
                    if let s = sousTitre { Text("– " + s).font(.subheadline) }
                }
                .strikethrough(item.annule)
                if let pt = moteur.texte(item.place), !item.annule {
                    Text(pt.cours + (pt.etape.isEmpty ? "" : " · \(pt.etape) (\(pt.etapePos))"))
                        .font(.caption.weight(.semibold))
                }
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if item.type != .libre { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 9).padding(.leading, 14).padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fond, in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(bande).frame(width: 6)
        }
        .foregroundStyle(item.type == .libre ? Color.secondary : Color.primary)
    }

    private var icone: String {
        switch item.type {
        case .cours: return item.groupe?.icone ?? "person.2"
        case .libre: return "cup.and.saucer"
        case .evenement: return item.evenement?.horaireId != nil ? "repeat" : (item.evenement?.type.symbole ?? "calendar")
        }
    }
    private var titre: String {
        switch item.type {
        case .cours: return item.groupe?.nom ?? "?"
        case .libre: return (item.periode?.nom ?? "") + " — libre"
        case .evenement: return item.evenement?.titre ?? ""
        }
    }
    private var sousTitre: String? {
        guard item.type == .cours else { return nil }
        if item.annule { return "Annulé" }
        return moteur.texte(item.place)?.titre
    }
    private var detail: String {
        switch item.type {
        case .cours:
            var parts: [String] = []
            if avecHeure { parts.append(D.hm(item.debut)) }
            parts.append(item.periode?.nom ?? "")
            if !item.local.isEmpty { parts.append("local " + item.local) }
            if !item.note.isEmpty { parts.append("✎ note") }
            return parts.joined(separator: " · ")
        case .libre: return ""
        case .evenement:
            guard let e = item.evenement else { return "" }
            let h = e.journee ? "Toute la journée" : D.hm(e.debut) + (e.fin.isEmpty ? "" : "–" + D.hm(e.fin))
            return h + " · " + (e.horaireId != nil ? e.note : e.type.label) + (e.lieu.isEmpty ? "" : " · " + e.lieu)
        }
    }
    private var fond: Color {
        switch item.type {
        case .cours: return Theme.couleur(item.groupe?.couleur).fond
        case .libre: return Color.white
        case .evenement: return (item.evenement?.type.sansEcole ?? false) ? Theme.couleur("gris").fond : Theme.lavande
        }
    }
    private var bande: Color {
        switch item.type {
        case .cours: return Theme.couleur(item.groupe?.couleur).bande
        case .libre: return Theme.ligne
        case .evenement: return (item.evenement?.type.sansEcole ?? false) ? Theme.couleur("gris").bande : Theme.lavandeBande
        }
    }
}

// MARK: - Carte « En ce moment »

struct MaintenantCarte: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let m = store.moteur
            let date = D.iso(ctx.date), now = D.hhmm(ctx.date)
            let tous = m.items(date).filter { !$0.debut.isEmpty }
            let actifs = tous.filter { $0.type != .libre }
            let cur = actifs.first { $0.debut <= now && now < $0.fin }
            let suivant = actifs.first { $0.debut > now }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(D.long(date)).font(.subheadline.bold())
                    Spacer()
                    Text(m.jourCycle(date).map { m.etiquetteJour($0) } ?? "Pas d’école")
                        .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Theme.vert, lineWidth: 1.5))
                }
                if m.jourCycle(date) == nil && actifs.isEmpty {
                    Text("Pas d’école aujourd’hui").font(.title3.bold())
                    if let n = m.prochainJourEcole(apres: date) {
                        Text("Prochain jour d’école : " + D.long(n)).font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let x = cur ?? suivant {
                    bloc(x, etiquette: cur != nil ? "En ce moment" : "Prochaine période")
                    if cur != nil, let s = suivant {
                        Divider()
                        bloc(s, etiquette: "Ensuite")
                    }
                } else {
                    Text("Journée terminée").font(.title3.bold())
                }
            }
            .carte()
        }
    }

    @ViewBuilder func bloc(_ x: ItemJour, etiquette: String) -> some View {
        let m = store.moteur
        VStack(alignment: .leading, spacing: 3) {
            Text("\(etiquette.uppercased()) · \(D.hm(x.debut))\(x.fin.isEmpty ? "" : "–" + D.hm(x.fin))")
                .font(.caption.weight(.heavy)).foregroundStyle(Theme.vert2)
            if x.type == .cours {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.couleur(x.groupe?.couleur).bande).frame(width: 6, height: 22)
                    Text(x.groupe?.nom ?? "").font(.title3.bold())
                }
                if x.annule {
                    Text("Cours annulé").font(.subheadline.bold())
                } else if let pt = m.texte(x.place) {
                    Text(pt.titre + (pt.etape.isEmpty ? "" : " — " + pt.etape)).font(.subheadline)
                    Text(pt.cours).font(.caption.bold())
                } else {
                    Text("Rien de planifié").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let e = x.evenement {
                Label(e.titre, systemImage: e.type.symbole).font(.title3.bold())
            }
        }
    }
}
