import SwiftUI

// MARK: - Aujourd'hui : le cours en ce moment, sa planification, la note à ne pas oublier, puis la suite

private enum Ajout: String, Identifiable {
    case evenement, pratique, activite, groupe
    var id: String { rawValue }
}

struct AccueilView: View {
    @EnvironmentObject var store: Store
    @State private var cours: CleId?
    @State private var aAnnuler: ItemJour?
    @State private var ajout: Ajout?
    @State private var reglages = false
    @State private var occurrence: Evenement?
    @State private var evenement: Evenement?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { ctx in
                let m = store.moteur
                let date = D.iso(ctx.date), h = D.hhmm(ctx.date)
                let cd = m.jourCycle(date)
                let tous = m.items(date).filter { !$0.debut.isEmpty }
                let actifs = tous.filter { $0.type != .libre }
                let cur = actifs.first { $0.debut <= h && h < $0.fin }
                    ?? tous.first { $0.type == .libre && $0.debut <= h && h < $0.fin }
                let suite = actifs.filter { $0.debut > h || ($0.debut <= h && h < $0.fin && $0.id != cur?.id) }
                    .filter { $0.id != cur?.id }
                let journee = m.items(date).filter { $0.debut.isEmpty && $0.type == .evenement }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        entete(date: date, cd: cd)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(journee) { x in
                                if let e = x.evenement {
                                    Label(e.titre, systemImage: e.type.symbole)
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Theme.lavande, in: RoundedRectangle(cornerRadius: 14))
                                }
                            }

                            heros(cur: cur, suivant: cur == nil ? Moteur.prochain(tous, apres: h) : suite.first, apres: suite.first, m: m, date: date, h: h, cd: cd)

                            ForEach(alertes(m), id: \.self) { a in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(hex: "8a5a12"))
                                    Text(a).font(.footnote).foregroundStyle(Color(hex: "5b3d0c"))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(hex: "fff4e0"), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "e8c88f")))
                            }
                            if !store.data.config.hebdo && m.sansEcole.isEmpty {
                                NavigationLink { SansEcoleView() } label: {
                                    Label("Ajoute tes journées pédagogiques et congés pour que le cycle soit exact.", systemImage: "exclamationmark.triangle")
                                        .font(.footnote).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Color(hex: "fff4e0"), in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }

                            let reste = (cur == nil && Moteur.prochain(tous, apres: h)?.type != .libre) ? Array(suite.dropFirst()) : suite
                            if !reste.isEmpty {
                                Text("ENSUITE").font(.caption.weight(.heavy)).foregroundStyle(.secondary).padding(.horizontal, 4)
                                VStack(spacing: 0) {
                                    ForEach(Array(reste.enumerated()), id: \.element.id) { i, x in
                                        Button { ouvrir(x) } label: { ligne(x, m: m) }.buttonStyle(.plain)
                                        if i < reste.count - 1 { Divider().padding(.leading, 14) }
                                    }
                                }
                                .background(Theme.carte, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
                .background(Theme.fond)
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $reglages) { ReglagesView() }
            .sheet(item: $cours) { CoursSheet(cle: $0.id) }
            .sheet(item: $occurrence) { OccurrenceSheet(occ: $0) }
            .sheet(item: $evenement) { EvenementEditeur(original: $0) }
            .sheet(item: $ajout) { a in
                switch a {
                case .evenement: EvenementEditeur(original: Evenement(titre: "", date: D.today()))
                case .pratique: HoraireEditeur(original: HoraireSup(nom: "", debut: max(D.today(), store.data.config.debut), fin: store.data.config.fin))
                case .activite: ActiviteEditeur(original: nil, groupeInitial: nil)
                case .groupe: GroupeEditeur(original: nil)
                }
            }
            .confirmationDialog("Annuler ce cours?", isPresented: Binding(get: { aAnnuler != nil }, set: { if !$0 { aAnnuler = nil } }), titleVisibility: .visible) {
                if let x = aAnnuler {
                    Button(x.annule ? "Rétablir le cours" : "Pas de cours (décaler la planif)", role: x.annule ? nil : .destructive) {
                        let k = x.cle
                        store.maj { d in
                            if let i = d.annulations.firstIndex(of: k) { d.annulations.remove(at: i) } else { d.annulations.append(k) }
                        }
                    }
                }
            } message: {
                Text("La planification de ce groupe glisse au cours suivant.")
            }
        }
    }

    // MARK: En-tête

    private func entete(date: String, cd: Int?) -> some View {
        let m = store.moteur
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(D.long(date) + " · " + (cd.map { m.etiquetteJour($0) } ?? "Pas d’école"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: "cfdcc6"))
                Text("Aujourd’hui").font(.system(size: 32, weight: .heavy))
            }
            Spacer()
            Menu {
                Button { ajout = .evenement } label: { Label("Événement", systemImage: "calendar.badge.plus") }
                Button { ajout = .pratique } label: { Label("Pratique régulière", systemImage: "repeat") }
                Button { ajout = .activite } label: { Label("Activité", systemImage: "square.stack.3d.up") }
                Button { ajout = .groupe } label: { Label("Groupe", systemImage: "person.2") }
            } label: {
                rond("plus")
            }
            .accessibilityLabel("Ajouter")
            Button { reglages = true } label: { rond("gearshape") }
                .accessibilityLabel("Réglages")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 22)
        .background(Theme.vert)
    }

    private func rond(_ icone: String) -> some View {
        Image(systemName: icone).font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(Theme.vert3, in: Circle())
            .foregroundStyle(.white)
    }

    // MARK: La grande carte

    @ViewBuilder private func heros(cur: ItemJour?, suivant: ItemJour?, apres: ItemJour?, m: Moteur, date: String, h: String, cd: Int?) -> some View {
        let x = cur ?? suivant
        VStack(alignment: .leading, spacing: 10) {
            if let x {
                let etiquette = cur != nil ? "EN CE MOMENT" : "PROCHAIN · " + D.hm(x.debut)
                Text(etiquette + (x.periode.map { " · " + $0.nom.uppercased() } ?? ""))
                    .font(.caption.weight(.heavy)).foregroundStyle(.secondary)

                if x.type == .libre {
                    Text("Période libre").font(.system(size: 28, weight: .heavy))
                    if let s = apres, s.id != x.id { Text("Ensuite à \(D.hm(s.debut)) : \(nomItem(s))").font(.subheadline) }
                } else if x.type == .cours, let g = x.groupe {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.couleur(g.couleur).bande).frame(width: 6, height: 30)
                        Text(g.nom).font(.system(size: 30, weight: .heavy))
                        if !x.local.isEmpty { Text("Local \(x.local)").font(.footnote).foregroundStyle(.secondary) }
                    }
                    if x.annule {
                        Text("Cours annulé").font(.headline)
                    } else if let pt = m.texte(x.place) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pt.titre).font(.headline)
                            Text(pt.cours + (pt.etape.isEmpty ? "" : " · " + pt.etape)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Rien de planifié").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !x.rappel.isEmpty { rappel(x, m: m) }
                    if !x.note.isEmpty {
                        Label(x.note, systemImage: "pencil.line").font(.subheadline)
                    }
                } else if let e = x.evenement {
                    Label(e.titre, systemImage: e.horaireId != nil ? "repeat" : e.type.symbole).font(.title2.bold())
                    let sous = [e.horaireId != nil ? e.note : e.type.label, e.lieu].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sous.isEmpty { Text(sous).font(.subheadline).foregroundStyle(.secondary) }
                }

                if cur != nil, !x.fin.isEmpty {
                    let total = Double(max(1, D.minutes(x.fin) - D.minutes(x.debut)))
                    let fait = Double(max(0, D.minutes(h) - D.minutes(x.debut)))
                    ProgressView(value: min(fait, total), total: total).tint(Theme.vert)
                    HStack {
                        Text(D.hm(x.debut))
                        Spacer()
                        Text("fin \(D.hm(x.fin)) · encore \(max(0, D.minutes(x.fin) - D.minutes(h))) min")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                if x.type == .cours {
                    HStack(spacing: 8) {
                        Button { cours = CleId(id: x.cle) } label: {
                            Text(x.note.isEmpty ? "Ajouter une note" : "Modifier la note").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered).tint(Theme.vert)
                        if !x.annuleParEvenement {
                            Button { aAnnuler = x } label: {
                                Text(x.annule ? "Rétablir le cours" : "Annuler ce cours").frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered).tint(Color(hex: "8a2f22"))
                        }
                    }
                    .font(.subheadline.bold())
                }
            } else if cd == nil {
                Text("AUJOURD’HUI").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Text("Pas d’école").font(.system(size: 28, weight: .heavy))
                if let n = m.prochainJourEcole(apres: date) {
                    Text("Retour : " + D.long(n)).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("AUJOURD’HUI").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Text("Journée terminée").font(.system(size: 28, weight: .heavy))
                if let n = m.prochainJourEcole(apres: date), let premier = m.items(n).first(where: { $0.type == .cours }) {
                    Text("Demain : \(nomItem(premier)) à \(D.hm(premier.debut))" + (n == D.add(date, 1) ? "" : " (\(D.court(n).lowercased()))"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.carte, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private func rappel(_ x: ItemJour, m: Moteur) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("NOTE DU DERNIER COURS").font(.caption2.weight(.heavy))
                Text(x.rappel).font(.subheadline)
                Button("C’est fait") {
                    if let r = m.rappel(x.cle) {
                        store.maj { d in if !d.notesFaites.contains(r.cle) { d.notesFaites.append(r.cle) } }
                    }
                }
                .font(.subheadline.bold())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.sauge.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.vert2, lineWidth: 1))
    }

    // MARK: Lignes « Ensuite »

    private func ligne(_ x: ItemJour, m: Moteur) -> some View {
        HStack(spacing: 12) {
            Text(D.hm(x.debut)).font(.subheadline.bold().monospacedDigit()).frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 2)
                .fill(x.type == .cours ? Theme.couleur(x.groupe?.couleur).bande : Theme.lavandeBande)
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(nomItem(x)).font(.headline)
                Text(sousTexte(x, m: m)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !x.rappel.isEmpty {
                    Label(x.rappel, systemImage: "note.text").font(.caption.bold()).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func nomItem(_ x: ItemJour) -> String {
        switch x.type {
        case .cours: return x.groupe?.nom ?? "Cours"
        case .evenement: return x.evenement?.titre ?? "Événement"
        case .libre: return "Période libre"
        }
    }

    private func sousTexte(_ x: ItemJour, m: Moteur) -> String {
        if x.type == .cours {
            if x.annule { return "Cours annulé" }
            if let pt = m.texte(x.place) { return pt.titre + " · " + pt.cours }
            return "Rien de planifié"
        }
        if let e = x.evenement {
            return [e.horaireId != nil ? e.note : e.type.label, e.lieu].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return ""
    }

    private func ouvrir(_ x: ItemJour) {
        switch x.type {
        case .cours: cours = CleId(id: x.cle)
        case .evenement:
            if x.evenement?.horaireId != nil { occurrence = x.evenement } else { evenement = x.evenement }
        case .libre: break
        }
    }

    /// Avertissements utiles seulement : activités qui ne finissent pas avant la fin de l'année.
    private func alertes(_ m: Moteur) -> [String] {
        store.data.activites.compactMap { a in
            let s = m.stats(a)
            guard s.manquantes > 0 else { return nil }
            return "« \(a.titre) » ne finit pas avant la fin de l’année : \(s.manquantes) période\(s.manquantes > 1 ? "s" : "") manquante\(s.manquantes > 1 ? "s" : "")."
        }
    }
}

struct Tuile: View {
    let icone: String
    let titre: String
    let sousTitre: String
    var miseEnAvant = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icone).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.vert).padding(.bottom, 8)
            Text(titre).font(.title3.bold()).foregroundStyle(.primary)
            Text(sousTitre).font(.footnote).foregroundStyle(Color(hex: "3c433e"))
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(miseEnAvant ? Theme.sauge : Theme.tuile, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct Montagnes: Shape {
    var decalage: CGFloat = 0
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts: [CGFloat] = decalage == 0 ? [0.55, 0.15, 0.5, 0.0, 0.45, 0.2, 0.55, 0.1, 0.4] : [0.6, 0.3, 0.55, 0.2, 0.6, 0.25, 0.5]
        p.move(to: CGPoint(x: 0, y: r.maxY))
        for (i, y) in pts.enumerated() {
            p.addLine(to: CGPoint(x: r.width * CGFloat(i) / CGFloat(pts.count - 1), y: r.minY + r.height * y))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
