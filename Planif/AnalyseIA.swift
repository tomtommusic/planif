// Analyse des dates avec le modèle d'Apple Intelligence (sur l'appareil, gratuit, hors ligne).
// Si ce fichier cause une erreur de compilation, tu peux le supprimer du projet :
// l'import utilisera alors seulement la détection simple des dates.

#if canImport(FoundationModels)
import Foundation
import FoundationModels

@Generable
struct EvenementIA {
    @Guide(description: "Titre court de l'événement, en français")
    var titre: String
    @Guide(description: "Date de début au format AAAA-MM-JJ")
    var date: String
    @Guide(description: "Date de fin au format AAAA-MM-JJ si l'événement dure plusieurs jours, sinon une chaîne vide")
    var dateFin: String
    @Guide(description: "Heure de début au format HH:mm, ou une chaîne vide")
    var debut: String
    @Guide(description: "Heure de fin au format HH:mm, ou une chaîne vide")
    var fin: String
    @Guide(description: "Un seul de ces mots : pedago, conge, reunion, bulletin, spectacle, sortie, cours, rdv, autre")
    var type: String
}

@Generable
struct ListeEvenementsIA {
    @Guide(description: "Tous les événements datés trouvés dans le texte, un par date")
    var evenements: [EvenementIA]
}

enum AnalyseIA {
    static var disponible: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func extraire(_ texte: String, config: Config) async throws -> [Detecte] {
        guard disponible else { return [] }
        let consignes = """
        Tu extrais les dates d’un document scolaire québécois pour l’agenda d’un enseignant.
        L’année scolaire va du \(config.debut) au \(config.fin). Si l’année n’est pas écrite :
        août à décembre = \(config.debut.prefix(4)), janvier à juillet = \(config.fin.prefix(4)).
        Une rencontre répétée donne une entrée par date. Les journées pédagogiques sont « pedago »,
        les congés, fériés, relâche et vacances sont « conge ». N’invente aucune date.
        """
        var out: [Detecte] = []
        for morceau in decouper(texte, taille: 2500).prefix(10) {
            let session = LanguageModelSession(instructions: consignes)
            let reponse = try await session.respond(to: "Texte du document :\n\(morceau)", generating: ListeEvenementsIA.self)
            for e in reponse.content.evenements where estDate(e.date) {
                let type = TypeEvenement(rawValue: e.type.lowercased()) ?? Heuristique.devinerType(e.titre)
                out.append(Detecte(titre: e.titre, date: e.date, dateFin: estDate(e.dateFin) ? e.dateFin : "",
                                   debut: estHeure(e.debut) ? e.debut : "", fin: estHeure(e.fin) ? e.fin : "", type: type))
            }
        }
        return out
    }

    private static func estDate(_ s: String) -> Bool {
        s.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
    }
    private static func estHeure(_ s: String) -> Bool {
        s.range(of: "^\\d{2}:\\d{2}$", options: .regularExpression) != nil
    }

    /// Le modèle sur l'appareil a une fenêtre limitée : on découpe le texte par lignes.
    private static func decouper(_ texte: String, taille: Int) -> [String] {
        var morceaux: [String] = []
        var courant = ""
        for ligne in texte.components(separatedBy: .newlines) {
            if courant.count + ligne.count > taille && !courant.isEmpty {
                morceaux.append(courant)
                courant = ""
            }
            courant += ligne + "\n"
        }
        if !courant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { morceaux.append(courant) }
        return morceaux
    }
}
#endif
