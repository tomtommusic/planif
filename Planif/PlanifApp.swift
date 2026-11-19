import SwiftUI
import WidgetKit

@main
struct PlanifApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environmentObject(store)
                .tint(Theme.vert2)
                .preferredColorScheme(.light)
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var moteur: Moteur

    init() {
        let d = Stockage.charger() ?? AppData.vide()
        data = d
        moteur = Moteur(d)
    }

    /// Toute modification passe par ici : sauvegarde, recalcul et mise à jour du widget.
    func maj(_ f: (inout AppData) -> Void) {
        var d = data
        f(&d)
        data = d
        moteur = Moteur(d)
        Stockage.sauver(d)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func groupe(_ id: String) -> Groupe? { data.groupes.first { $0.id == id } }
    func activite(_ id: String) -> Activite? { data.activites.first { $0.id == id } }

    func nouveauGroupe(_ nom: String, dans d: inout AppData) {
        let pris = Set(d.groupes.map { $0.couleur })
        let couleur = Theme.palette.first { !pris.contains($0.id) }?.id ?? Theme.palette[d.groupes.count % Theme.palette.count].id
        d.groupes.append(Groupe(nom: nom, couleur: couleur))
    }

    func ajouterSansEcole(_ titre: String, date: String, fin: String, type: TypeEvenement, dans d: inout AppData) -> Bool {
        if d.evenements.contains(where: { $0.date == date && $0.type.sansEcole }) { return false }
        d.evenements.append(Evenement(titre: titre, type: type, date: date, dateFin: fin > date ? fin : "", journee: true))
        return true
    }
}

struct RacineView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if !store.data.config.onboarded {
            AssistantView()
        } else {
            TabView {
                Tab("Aujourd’hui", systemImage: "sun.max") { AccueilView() }
                Tab("Agenda", systemImage: "list.bullet.rectangle") { AgendaView() }
                Tab("Calendrier", systemImage: "calendar") { CalendrierView() }
                Tab("Groupes", systemImage: "person.2") { GroupesView() }
                Tab("Plus", systemImage: "ellipsis") { PlusView() }
            }
        }
    }
}
