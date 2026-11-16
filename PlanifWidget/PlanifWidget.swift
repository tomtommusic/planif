import WidgetKit
import SwiftUI

// MARK: - Données du widget

struct EntreePlanif: TimelineEntry {
    let date: Date
    let data: AppData?
}

struct FournisseurPlanif: TimelineProvider {
    func placeholder(in context: Context) -> EntreePlanif { EntreePlanif(date: .now, data: nil) }

    func getSnapshot(in context: Context, completion: @escaping (EntreePlanif) -> Void) {
        completion(EntreePlanif(date: .now, data: Stockage.charger()))
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
        let limite = maintenant.addingTimeInterval(8 * 3600)
        let entrees = dates.filter { $0 >= maintenant && $0 <= limite }.sorted().map { EntreePlanif(date: $0, data: data) }
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct VuePlanifWidget: View {
    @Environment(\.widgetFamily) private var famille
    @Environment(\.widgetRenderingMode) private var rendu
    let entree: EntreePlanif

    var body: some View {
        if let data = entree.data, data.config.onboarded {
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
        let jour = D.iso(entree.date)
        let h = D.hhmm(entree.date)
        let tous = m.items(jour).filter { !$0.debut.isEmpty }
        let actifs = tous.filter { $0.type != .libre }
        let cur = actifs.first { $0.debut <= h && h < $0.fin }
        let suivants = actifs.filter { $0.debut > h }
        let focus = cur ?? suivants.first
        let cd = m.jourCycle(jour)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(famille == .systemLarge ? D.court(jour) : "Planif", systemImage: "calendar")
                Spacer()
                Text(cd.map { m.etiquetteJour($0) } ?? "—")
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)

            switch famille {
            case .systemSmall:
                bloc(focus, enCours: cur != nil, m: m, jour: jour, h: h, cd: cd)
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    bloc(focus, enCours: cur != nil, m: m, jour: jour, h: h, cd: cd)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ENSUITE").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                        let reste = suivants.filter { $0.id != focus?.id }.prefix(3)
                        if reste.isEmpty { Text("Rien d’autre aujourd’hui").font(.caption).foregroundStyle(.secondary) }
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

    @ViewBuilder private func bloc(_ x: ItemJour?, enCours: Bool, m: Moteur, jour: String, h: String, cd: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let x {
                Text(enCours ? "EN CE MOMENT" : "PROCHAIN · \(D.hm(x.debut))").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    bande(x).frame(width: 5, height: 20)
                    Text(nom(x)).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                }
                if let s = sousTexte(x, m) { Text(s).font(.caption).lineLimit(2) }
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
                Text("AUJOURD’HUI").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                Text("Pas d’école").font(.title3.bold())
                if let n = m.prochainJourEcole(apres: jour) { Text("Retour " + D.court(n).lowercased()).font(.caption) }
                Spacer(minLength: 0)
            } else {
                Text("AUJOURD’HUI").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                Text("Journée terminée").font(.title3.bold())
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
        case .evenement: return x.evenement?.type.label
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
