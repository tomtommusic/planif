import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct IconeChoix: Identifiable { let id: String; let nom: String }

struct CouleurGroupe: Identifiable {
    let id: String
    let nom: String
    let bande: Color
    let fond: Color
}

enum Theme {
    static let vert = Color(hex: "2e4637")
    static let vert2 = Color(hex: "3b5f47")
    static let vert3 = Color(hex: "46694f")
    static let sauge = Color(hex: "b8cba6")
    static let tuile = Color(hex: "ebeae4")
    static let fond = Color(hex: "f3f2ee")
    static let carte = Color(hex: "fbfaf7")
    static let ligne = Color(hex: "d9d7cf")
    static let lavande = Color(hex: "ece6f3")
    static let lavandeBande = Color(hex: "7d62a6")

    /// Le nom du groupe est toujours écrit : la couleur n'est jamais la seule information.
    static let palette: [CouleurGroupe] = [
        CouleurGroupe(id: "sauge", nom: "Vert sauge", bande: Color(hex: "6a9a48"), fond: Color(hex: "e2ecd6")),
        CouleurGroupe(id: "bleu", nom: "Bleu", bande: Color(hex: "4a82b5"), fond: Color(hex: "dbe8f4")),
        CouleurGroupe(id: "peche", nom: "Pêche", bande: Color(hex: "cf8a2c"), fond: Color(hex: "f8e6cd")),
        CouleurGroupe(id: "lavande", nom: "Lavande", bande: Color(hex: "8466b0"), fond: Color(hex: "e9e1f2")),
        CouleurGroupe(id: "gris", nom: "Gris", bande: Color(hex: "767e78"), fond: Color(hex: "e7e8e4")),
        CouleurGroupe(id: "rose", nom: "Rose", bande: Color(hex: "bf5179"), fond: Color(hex: "f6dde6")),
        CouleurGroupe(id: "turquoise", nom: "Turquoise", bande: Color(hex: "2a8c86"), fond: Color(hex: "d5eeeb")),
        CouleurGroupe(id: "sable", nom: "Sable", bande: Color(hex: "9c8436"), fond: Color(hex: "f0e8cc")),
        CouleurGroupe(id: "brique", nom: "Brique", bande: Color(hex: "b0503a"), fond: Color(hex: "f4ddd5")),
        CouleurGroupe(id: "marine", nom: "Marine", bande: Color(hex: "33507b"), fond: Color(hex: "dbe2ef"))
    ]

    static func couleur(_ cle: String?) -> CouleurGroupe {
        palette.first { $0.id == cle } ?? palette[4]
    }

    static let icones: [IconeChoix] = [
        IconeChoix(id: "person.2", nom: "Groupe"), IconeChoix(id: "book", nom: "Français"), IconeChoix(id: "function", nom: "Mathématique"),
        IconeChoix(id: "flask", nom: "Sciences"), IconeChoix(id: "globe.americas", nom: "Univers social"), IconeChoix(id: "music.note", nom: "Musique"),
        IconeChoix(id: "paintpalette", nom: "Arts"), IconeChoix(id: "figure.run", nom: "Éduc. physique"), IconeChoix(id: "scalemass", nom: "Éthique"),
        IconeChoix(id: "pencil", nom: "Écriture"), IconeChoix(id: "square.stack.3d.up", nom: "Projet"), IconeChoix(id: "folder", nom: "Dossier")
    ]
}
