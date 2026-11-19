import Foundation

// MARK: - Modèle de données (partagé entre l'app et le widget)

struct Periode: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nom: String
    var debut: String   // "HH:mm"
    var fin: String     // "HH:mm"
}

struct Cellule: Codable, Hashable {
    var g: String            // id du groupe
    var local: String = ""
}

struct Eleve: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nom: String
    var note: String = ""
}

struct Groupe: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nom: String
    var couleur: String = "sauge"
    var icone: String = "person.2"
    var local: String = ""
    var eleves: [Eleve] = []
}

enum TypeEvenement: String, Codable, CaseIterable, Identifiable {
    case pedago, conge, reunion, bulletin, spectacle, sortie, cours, rdv, autre
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pedago: return "Journée pédagogique"
        case .conge: return "Congé"
        case .reunion: return "Réunion / comité"
        case .bulletin: return "Bulletin / parents"
        case .spectacle: return "Spectacle / concert"
        case .sortie: return "Sortie éducative"
        case .cours: return "Examen / cours spécial"
        case .rdv: return "Rendez-vous / pratique"
        case .autre: return "Autre"
        }
    }
    var symbole: String {
        switch self {
        case .pedago: return "book.closed"
        case .conge: return "sun.max"
        case .reunion: return "person.3"
        case .bulletin: return "doc.text"
        case .spectacle: return "music.mic"
        case .sortie: return "tree"
        case .cours: return "pencil"
        case .rdv: return "clock"
        case .autre: return "calendar"
        }
    }
    /// Les journées pédagogiques et les congés n'avancent pas le cycle.
    var sansEcole: Bool { self == .pedago || self == .conge }
}

enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case aucune, hebdo, cycle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aucune: return "Jamais"
        case .hebdo: return "Chaque semaine"
        case .cycle: return "Selon les jours du cycle"
        }
    }
}

struct Evenement: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var titre: String
    var type: TypeEvenement = .autre
    var date: String
    var dateFin: String = ""
    var journee: Bool = true
    var debut: String = ""
    var fin: String = ""
    var lieu: String = ""
    var note: String = ""
    var rec: Recurrence = .aucune
    var jours: [Int] = []          // 0 = dimanche … 6 = samedi (hebdo) ou numéros de jour de cycle
    var jusquau: String = ""
    var ecoleSeulement: Bool = true
    var annuleCours: Bool = false
    var exceptions: [String] = []
    /// Rempli seulement pour les occurrences générées par un horaire régulier (jamais enregistré).
    var horaireId: String? = nil
    var blocId: String? = nil
}

// MARK: - Horaires réguliers (pratiques, soirées…) jumelés à l'horaire de cours

struct BlocHoraire: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var titre: String
    var jours: [Int] = []          // 0 = dimanche … 6 = samedi, ou numéros de jour de cycle
    var debut: String = "18:30"
    var fin: String = "20:00"
    var lieu: String = ""
}

struct HoraireSup: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nom: String
    var rec: Recurrence = .hebdo   // .hebdo ou .cycle
    var ecoleSeulement: Bool = true
    var debut: String
    var fin: String
    var blocs: [BlocHoraire] = []
    var exceptions: [String] = []  // « idBloc|date » : occurrences annulées
}

struct Etape: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var titre: String
    var periodes: Int = 1
    var fait: Bool = false
}

struct Activite: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var titre: String
    var objectif: String = ""
    var groupes: [String] = []
    var debut: String = ""
    var etapes: [Etape] = []
    var nbPeriodes: Int = 1
    var ressources: String = ""
    var icone: String = "book"
}

struct Config: Codable, Hashable {
    var ecole: String = ""
    var debut: String
    var fin: String
    var refDate: String
    var refJour: Int = 1
    var cycleLen: Int = 9
    var hebdo: Bool = false
    /// Jours de cycle fixés à la main (0 = pas d'école).
    var cycleMap: [String: Int] = [:]
    var onboarded: Bool = false
}

struct AppData: Codable {
    var version: Int = 1
    var config: Config
    var periodes: [Periode]
    var cellules: [String: Cellule]     // clé "jour|idPeriode"
    var groupes: [Groupe]
    var evenements: [Evenement]
    var activites: [Activite]
    var annulations: [String]           // clés "idGroupe|date|idPeriode"
    var notes: [String: String]         // même clé
    var horairesSup: [HoraireSup]? = nil
    var notesFaitesOpt: [String]? = nil  // notes dont le rappel a été coché « C'est fait »

    var notesFaites: [String] {
        get { notesFaitesOpt ?? [] }
        set { notesFaitesOpt = newValue }
    }

    var horaires: [HoraireSup] {
        get { horairesSup ?? [] }
        set { horairesSup = newValue }
    }

    static func vide() -> AppData {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let y1 = m >= 7 ? y : y - 1
        let debut = String(format: "%04d-08-27", y1)
        let fin = String(format: "%04d-06-20", y1 + 1)
        return AppData(
            config: Config(debut: debut, fin: fin, refDate: debut),
            periodes: [
                Periode(id: "p1", nom: "Période 1", debut: "08:15", fin: "09:30"),
                Periode(id: "p2", nom: "Période 2", debut: "09:45", fin: "11:00"),
                Periode(id: "p3", nom: "Période 3", debut: "11:15", fin: "12:30"),
                Periode(id: "p4", nom: "Période 4", debut: "13:35", fin: "14:50")
            ],
            cellules: [:], groupes: [], evenements: [], activites: [], annulations: [], notes: [:]
        )
    }
}

// MARK: - Stockage partagé (App Group) pour que le widget lise les mêmes données

enum Stockage {
    static let groupeApp = "group.ca.tomtommusic.planif"

    static var url: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupeApp)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("planif.json")
    }

    static func charger() -> AppData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: data)
    }

    static func sauver(_ d: AppData) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(d) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
