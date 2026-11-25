import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Navigation entre les jours (revient seule à aujourd'hui)

enum NavWidget {
    /// Délai avant le retour automatique à aujourd'hui.
    static let duree: TimeInterval = 120
    private static var defauts: UserDefaults? { UserDefaults(suiteName: Stockage.groupeApp) }

    static func etat(_ maintenant: Date = .now) -> (decalage: Int, expire: Date?) {
        guard let d = defauts else { return (0, nil) }
        let exp = Date(timeIntervalSince1970: d.double(forKey: "widgetExpire"))
        let dec = d.integer(forKey: "widgetDecalage")
        guard dec != 0, exp > maintenant else { return (0, nil) }
        return (dec, exp)
    }

    static func regler(_ decalage: Int) {
        guard let d = defauts else { return }
        d.set(decalage, forKey: "widgetDecalage")
        d.set(decalage == 0 ? 0 : Date.now.addingTimeInterval(duree).timeIntervalSince1970, forKey: "widgetExpire")
    }
}

struct ChangerJourWidget: AppIntent {
    static var title: LocalizedStringResource = "Changer le jour affiché"
    static var isDiscoverable: Bool = false

    /// +1 : jour suivant, -1 : jour précédent, 0 : retour à aujourd'hui.
    @Parameter(title: "Sens") var sens: Int

    init() { sens = 0 }
    init(sens: Int) { self.sens = sens }

    func perform() async throws -> some IntentResult {
        let actuel = NavWidget.etat().decalage
        NavWidget.regler(sens == 0 ? 0 : max(-14, min(60, actuel + sens)))
        return .result()
    }
}

// MARK: - Données du widget

struct EntreePlanif: TimelineEntry {
    let date: Date
    let data: AppData?
    var decalage: Int = 0
}

struct FournisseurPlanif: TimelineProvider {
    func placeholder(in context: Context) -> EntreePlanif { EntreePlanif(date: .now, data: nil) }

    func getSnapshot(in context: Context, completion: @escaping (EntreePlanif) -> Void) {
        completion(EntreePlanif(date: .now, data: Stockage.charger(), decalage: NavWidget.etat().decalage))
    }

    /// Une entrée au début et à la fin de chaque période, plus toutes les 10 minutes pour la barre de progression.
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreePlanif>) -> Void) {
        let data = Stockage.charger()
        let maintenant = Date()
        var dates: Set<Date> = [maintenant]
        if let data {
            let m = Moteur(data)
            for decalage in 0...1 {
                let jour = D.add(D.today(), decalage)
                for it in m.items(jour) where !it.debut.isEmpty {
                    dates.insert(D.dateTime(jour, it.debut))
                    if !it.fin.isEmpty { dates.insert(D.dateTime(jour, it.fin)) }
                }
            }
        }
        for i in 1...48 { dates.insert(maintenant.addingTimeInterval(Double(i) * 600)) }
        let nav = NavWidget.etat(maintenant)
        if let exp = nav.expire { dates.insert(exp) }
        let limite = maintenant.addingTimeInterval(8 * 3600)
        let entrees = dates.filter { $0 >= maintenant && $0 <= limite }.sorted().map { t in
            EntreePlanif(date: t, data: data, decalage: (nav.expire.map { t < $0 } ?? false) ? nav.decalage : 0)
        }
        completion(Timeline(entries: entrees, policy: .after(limite)))
    }
}

// MARK: - Widget

@main
struct PlanifWidgetBundle: WidgetBundle {
    var body: some Widget { PlanifWidget() }
}

struct PlanifWidget: Widget {
    let kind = "PlanifWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FournisseurPlanif()) { e in
            VuePlanifWidget(entree: e)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        }
        .configurationDisplayName("Planif")
        .description("La période en cours, ce qui est planifié et la suite de ta journée.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct VuePlanifWidget: View {
    @Environment(\.widgetFamily) private var famille
    @Environment(\.widgetRenderingMode) private var rendu
    let entree: EntreePlanif

    var body: some View {
        if let data = entree.data, data.config.onboarded,
           [.accessoryRectangular, .accessoryInline, .accessoryCircular].contains(famille) {
            accessoire(Moteur(data))
        } else if [.accessoryRectangular, .accessoryInline, .accessoryCircular].contains(famille) {
            Text("Planif")
        } else if let data = entree.data, data.config.onboarded {
            contenu(Moteur(data))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Planif", systemImage: "calendar").font(.caption.bold())
                Text("Ouvre Planif pour configurer ton horaire.").font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func contenu(_ m: Moteur) -> some View {
        let dec = entree.decalage
        let jour = D.add(D.iso(entree.date), dec)
        // Autre jour : rien « en cours », on montre la journée depuis le début.
        let h = dec == 0 ? D.hhmm(entree.date) : "00:00"
        let tous = m.items(jour).filter { !$0.debut.isEmpty }
        let actifs = tous.filter { $0.type != .libre }
        // En cours : un cours ou un événement, sinon la période libre (ex. : l'heure du dîner).
        let cur = actifs.first { $0.debut <= h && h < $0.fin } ?? tous.first { $0.type == .libre && $0.debut <= h && h < $0.fin }
        let suivants = actifs.filter { $0.debut > h }
        let focus = cur ?? Moteur.prochain(tous, apres: h)
        let cd = m.jourCycle(jour)

        VStack(alignment: .leading, spacing: 4) {
            entete(m, jour: jour, cd: cd, dec: dec)

            switch famille {
            case .systemSmall:
                bloc(focus, enCours: cur != nil, m: m, jour: jour, h: h, cd: cd, dec: dec)
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    bloc(focus, enCours: cur != nil, m: m, jour: jour, h: h, cd: cd, dec: dec)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ENSUITE").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                        let reste = suivants.filter { $0.id != focus?.id }.prefix(3)
                        if reste.isEmpty { Text(dec == 0 ? "Rien d’autre aujourd’hui" : "Rien d’autre ce jour-là").font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(reste)) { x in
                            HStack(spacing: 6) {
                                Text(D.hm(x.debut)).font(.caption.bold().monospacedDigit())
                                bande(x).frame(width: 4, height: 12)
                                Text(nom(x)).font(.caption).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                if tous.isEmpty {
                    Text(cd == nil ? "Pas d’école" : "Aucune période").font(.title3.bold()).padding(.top, 6)
                }
                ForEach(tous.prefix(8)) { x in
                    let passe = !x.fin.isEmpty && x.fin <= h
                    let maintenant = x.debut <= h && h < x.fin
                    HStack(spacing: 8) {
                        Text(D.hm(x.debut)).font(.caption.bold().monospacedDigit()).frame(width: 40, alignment: .leading)
                        bande(x).frame(width: 4, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(nom(x)).font(.subheadline.weight(maintenant ? .heavy : .semibold)).lineLimit(1)
                            if let s = sousTexte(x, m) { Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3).padding(.horizontal, 4)
                    .background(maintenant ? Color.gray.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .opacity(passe ? 0.5 : 1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Écran verrouillé (sous l'heure)

    @ViewBuilder private func accessoire(_ m: Moteur) -> some View {
        let jour = D.iso(entree.date)
        let h = D.hhmm(entree.date)
        let tous = m.items(jour).filter { !$0.debut.isEmpty }
        let actifs = tous.filter { $0.type != .libre }
        let cur = actifs.first { $0.debut <= h && h < $0.fin } ?? tous.first { $0.type == .libre && $0.debut <= h && h < $0.fin }
        let suivant = Moteur.prochain(tous, apres: h)
        let cd = m.jourCycle(jour)

        switch famille {
        case .accessoryInline:
            if let x = cur {
                Text("\(nom(x)) · jusqu’à \(D.hm(x.fin))")
            } else if let x = suivant {
                Text("Ensuite \(D.hm(x.debut)) · \(nom(x))")
            } else {
                Text(cd.map { m.etiquetteJour($0) + " · journée terminée" } ?? "Pas d’école")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let x = cur, !x.fin.isEmpty {
                    let total = Double(max(1, D.minutes(x.fin) - D.minutes(x.debut)))
                    let fait = Double(max(0, D.minutes(h) - D.minutes(x.debut)))
                    Gauge(value: min(fait, total), in: 0...total) {
                        Text(cd.map { "J\($0)" } ?? "")
                    } currentValueLabel: {
                        Text(x.type == .libre ? "libre" : nom(x)).minimumScaleFactor(0.5)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    VStack(spacing: 0) {
                        Text("Jour").font(.caption2)
                        Text(cd.map { "\($0)" } ?? "—").font(.title2.bold())
                    }
                }
            }
        default:
            // Même présentation que le petit widget de l'écran d'accueil, en format compact.
            let focus = cur ?? suivant
            let etiquette = cd.map { m.etiquetteJour($0) } ?? ""
            VStack(alignment: .leading, spacing: 1) {
                if let x = focus {
                    Text((cur != nil ? "EN CE MOMENT" : "PROCHAIN · " + D.hm(x.debut)) + (etiquette.isEmpty ? "" : " · " + etiquette))
                        .font(.caption2.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 3, height: 15)
                        Text(nom(x)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let s = sousTexte(x, m) {
                        Text(s).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    if cur != nil, !x.fin.isEmpty {
                        let total = Double(max(1, D.minutes(x.fin) - D.minutes(x.debut)))
                        let fait = Double(max(0, D.minutes(h) - D.minutes(x.debut)))
                        HStack(spacing: 4) {
                            ProgressView(value: min(fait, total), total: total).progressViewStyle(.linear)
                            Text("fin " + D.hm(x.fin)).font(.caption2.monospacedDigit())
                        }
                    } else if let n = suivant, n.id != x.id {
                        Text("Ensuite \(D.hm(n.debut)) · \(nom(n))").font(.caption2).lineLimit(1)
                    }
                } else {
                    Text(cd.map { m.etiquetteJour($0).uppercased() } ?? "AUJOURD’HUI").font(.caption2.weight(.heavy))
                    Text(cd == nil ? "Pas d’école" : "Journée terminée").font(.headline)
                    if let n = m.prochainJourEcole(apres: jour) { Text("Retour " + D.court(n).lowercased()).font(.caption2) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetAccentable()
        }
    }

    /// En-tête : ‹ jour › — les flèches changent de jour, le titre ramène à aujourd'hui.
    @ViewBuilder private func entete(_ m: Moteur, jour: String, cd: Int?, dec: Int) -> some View {
        let etiquette = cd.map { m.etiquetteJour($0) } ?? "—"
        HStack(spacing: 4) {
            Button(intent: ChangerJourWidget(sens: -1)) {
                Image(systemName: "chevron.left").frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(intent: ChangerJourWidget(sens: 0)) {
                HStack(spacing: 4) {
                    Text(nomJour(jour, dec)).lineLimit(1).minimumScaleFactor(0.7)
                    if famille != .systemSmall || dec == 0 { Text("· " + etiquette).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(intent: ChangerJourWidget(sens: 1)) {
                Image(systemName: "chevron.right").frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.caption2.bold())
        .foregroundStyle(dec == 0 ? Color.secondary : Color.primary)
    }

    private func nomJour(_ jour: String, _ dec: Int) -> String {
        switch dec {
        case 0: return famille == .systemLarge ? "Aujourd’hui · " + D.court(jour) : "Aujourd’hui"
        case 1: return famille == .systemSmall ? "Demain" : "Demain · " + D.court(jour)
        case -1: return famille == .systemSmall ? "Hier" : "Hier · " + D.court(jour)
        default: return D.court(jour)
        }
    }

    @ViewBuilder private func bloc(_ x: ItemJour?, enCours: Bool, m: Moteur, jour: String, h: String, cd: Int?, dec: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let x {
                Text(enCours ? "EN CE MOMENT" : (dec == 0 ? "PROCHAIN" : "PREMIER") + " · \(D.hm(x.debut))").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    bande(x).frame(width: 5, height: 20)
                    Text(nom(x)).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                }
                if let s = sousTexte(x, m) { Text(s).font(.caption).lineLimit(2) }
                if !x.rappel.isEmpty {
                    Label(x.rappel, systemImage: "note.text").font(.caption.bold()).lineLimit(1)
                }
                Spacer(minLength: 0)
                if enCours, !x.fin.isEmpty {
                    let total = Double(max(1, D.minutes(x.fin) - D.minutes(x.debut)))
                    let fait = Double(max(0, D.minutes(h) - D.minutes(x.debut)))
                    ProgressView(value: min(fait, total), total: total).tint(.primary)
                    HStack { Text(D.hm(x.debut)); Spacer(); Text("fin " + D.hm(x.fin)) }.font(.caption2).foregroundStyle(.secondary)
                } else if !x.local.isEmpty {
                    Text("Local " + x.local).font(.caption2).foregroundStyle(.secondary)
                }
            } else if cd == nil {
                Text("Pas d’école").font(.title3.bold())
                if let n = m.prochainJourEcole(apres: jour) { Text("Retour " + D.court(n).lowercased()).font(.caption) }
                Spacer(minLength: 0)
            } else {
                Text(dec == 0 ? "Journée terminée" : "Rien à l’horaire").font(.title3.bold())
                Spacer(minLength: 0)
            }
        }
    }

    private func nom(_ x: ItemJour) -> String {
        switch x.type {
        case .cours: return x.groupe?.nom ?? "?"
        case .evenement: return x.evenement?.titre ?? ""
        case .libre: return "Période libre"
        }
    }

    private func sousTexte(_ x: ItemJour, _ m: Moteur) -> String? {
        switch x.type {
        case .cours:
            if x.annule { return "Cours annulé" }
            if let pt = m.texte(x.place) { return pt.titre + " · " + pt.cours }
            return x.periode?.nom
        case .evenement:
            guard let e = x.evenement else { return nil }
            return e.horaireId != nil ? e.note : e.type.label
        case .libre: return x.periode?.nom
        }
    }

    /// En mode Transparent ou Teinté, iOS affiche tout en une seule couleur : le nom reste toujours écrit.
    @ViewBuilder private func bande(_ x: ItemJour) -> some View {
        let couleur: Color = {
            switch x.type {
            case .cours: return Theme.couleur(x.groupe?.couleur).bande
            case .evenement: return Theme.lavandeBande
            case .libre: return Color.gray.opacity(0.4)
            }
        }()
        RoundedRectangle(cornerRadius: 2)
            .fill(rendu == .fullColor ? couleur : Color.primary.opacity(0.7))
            .widgetAccentable()
    }
}
