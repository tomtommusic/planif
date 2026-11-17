import SwiftUI
import UIKit
import PhotosUI
import PDFKit
import Vision
import UniformTypeIdentifiers

/// Un événement trouvé dans un document, à confirmer avant de l'ajouter.
struct Detecte: Identifiable {
    let id = UUID()
    var titre: String
    var date: String
    var dateFin: String
    var debut: String
    var fin: String
    var type: TypeEvenement
    var garder: Bool = true
}

/// Lecture d'un PDF ou d'une photo, entièrement sur l'iPhone :
/// texte (PDFKit ou Vision), puis dates (Apple Intelligence si disponible, sinon détection simple).
struct ImportView: View {
    @EnvironmentObject var store: Store
    @State private var photos: [PhotosPickerItem] = []
    @State private var choisirPDF = false
    @State private var occupe = false
    @State private var etat = ""
    @State private var resultats: [Detecte] = []
    @State private var methode = ""
    @State private var message: String?
    @State private var grille: ResultatGrille?
    @State private var gCycle = true
    @State private var gSansEcole = true
    @State private var gAnnee = true

    var body: some View {
        Form {
            Section {
                Text("Calendrier scolaire, dates de réunions, communications aux parents… Planif lit le document sur ton iPhone et te propose les dates à ajouter. Rien n’est envoyé ailleurs.")
                    .font(.footnote)
                PhotosPicker(selection: $photos, maxSelectionCount: 6, matching: .images) {
                    Label("Choisir des photos ou captures", systemImage: "photo.on.rectangle")
                }
                Button { choisirPDF = true } label: { Label("Choisir un PDF", systemImage: "doc.richtext") }
            }
            if occupe {
                Section { HStack { ProgressView(); Text(etat).padding(.leading, 8) } }
            }
            if let message { Section { Text(message) } }
            if let g = grille { sectionGrille(g) }
            if !resultats.isEmpty {
                Section {
                    ForEach($resultats) { $r in
                        Toggle(isOn: $r.garder) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(D.court(r.date) + (r.dateFin.isEmpty ? "" : " → " + D.court(r.dateFin)) + (r.debut.isEmpty ? "" : " · " + D.hm(r.debut)))
                                    .font(.subheadline.bold())
                                Text(r.titre)
                                Picker("Type", selection: $r.type) {
                                    ForEach(TypeEvenement.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("\(resultats.count) date(s) trouvée(s)")
                } footer: {
                    Text("Lu avec : \(methode). Vérifie chaque date : décoche ce qui est faux. Les journées pédagogiques et les congés décaleront le cycle.")
                }
                Section {
                    Button("Ajouter \(resultats.filter { $0.garder }.count) événement(s) à l’agenda") { ajouter() }
                        .bold()
                        .disabled(!resultats.contains { $0.garder })
                }
            }
        }
        .navigationTitle("Importer un document")
        .navigationBarTitleDisplayMode(.inline)
        .barreVerte()
        .fileImporter(isPresented: $choisirPDF, allowedContentTypes: [.pdf]) { r in
            if case .success(let url) = r { Task { await traiterPDF(url) } }
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task { await traiterPhotos(items) }
        }
    }

    // MARK: Lecture

    private func traiterPhotos(_ items: [PhotosPickerItem]) async {
        debut("Lecture des images…")
        var texte = ""
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data), let cg = img.cgImage {
                texte += await LectureTexte.ocr(cg) + "\n"
            }
        }
        photos = []
        await analyser(texte)
    }

    private func traiterPDF(_ url: URL) async {
        debut("Lecture du PDF…")
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else {
            fin("Impossible d’ouvrir ce PDF.")
            return
        }
        etat = "Recherche d’un calendrier en grille…"
        var g = ResultatGrille()
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i) { g.fusionner(GrilleCalendrier.analyser(page)) }
        }
        if g.cycle.count >= 20 {
            grille = g
            fin(nil)
            return
        }
        var texte = doc.string ?? ""
        if texte.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            etat = "PDF numérisé : lecture des pages…"
            texte = ""
            for i in 0..<min(doc.pageCount, 8) {
                if let page = doc.page(at: i), let cg = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox).cgImage {
                    texte += await LectureTexte.ocr(cg) + "\n"
                }
            }
        }
        await analyser(texte)
    }

    private func analyser(_ texte: String) async {
        guard !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fin("Aucun texte lisible. Essaie une photo plus nette.")
            return
        }
        let config = store.data.config
        var trouves: [Detecte] = []
        var via = "détection de dates"
        #if canImport(FoundationModels)
        if AnalyseIA.disponible {
            etat = "Apple Intelligence analyse le texte…"
            if let r = try? await AnalyseIA.extraire(texte, config: config), !r.isEmpty {
                trouves = r
                via = "Apple Intelligence"
            }
        }
        #endif
        if trouves.isEmpty { trouves = Heuristique.extraire(texte, config: config) }
        let existants = Set(store.data.evenements.map { $0.date + "|" + $0.titre.lowercased() })
        for i in trouves.indices where existants.contains(trouves[i].date + "|" + trouves[i].titre.lowercased()) {
            trouves[i].garder = false
        }
        resultats = trouves.sorted { $0.date < $1.date }
        methode = via
        fin(trouves.isEmpty ? "Aucune date trouvée dans ce document." : nil)
    }

    private func ajouter() {
        let choisis = resultats.filter { $0.garder }
        store.maj { d in
            for r in choisis {
                let journee = r.debut.isEmpty
                d.evenements.append(Evenement(titre: r.titre, type: r.type, date: r.date,
                                              dateFin: r.dateFin > r.date ? r.dateFin : "",
                                              journee: journee, debut: r.debut, fin: journee ? "" : r.fin))
            }
        }
        message = "\(choisis.count) événement(s) ajouté(s)."
        resultats = []
    }

    @ViewBuilder private func sectionGrille(_ g: ResultatGrille) -> some View {
        Section {
            Label("Calendrier scolaire en grille détecté", systemImage: "calendar").font(.headline)
            if let a = g.premier, let z = g.dernier {
                Text("\(g.cycle.count) jours de classe avec leur jour de cycle, du \(D.court(a).lowercased()) au \(D.court(z).lowercased()).")
            }
            Text("\(g.nbPedago) journée(s) pédagogique(s) et \(g.nbConge) journée(s) de congé" + (g.reprises.isEmpty ? "." : ", dont \(g.reprises.count) journée(s) de reprise possible."))
                .font(.subheadline)
            Toggle("Jours de cycle exacts pour toute l’année", isOn: $gCycle)
            Toggle("Ajouter les journées sans école à l’agenda", isOn: $gSansEcole)
            Toggle("Régler l’année scolaire sur ces dates", isOn: $gAnnee)
            Button("Appliquer") { appliquerGrille(g) }.bold()
        } footer: {
            Text("Les jours de cycle viennent des petits chiffres sous chaque date. Les pédagos et les congés viennent de la couleur des cases (bleu et vert).")
        }
    }

    private func appliquerGrille(_ g: ResultatGrille) {
        store.maj { d in
            if gCycle {
                for (date, j) in g.cycle { d.config.cycleMap[date] = j }
                for date in g.sansEcole.keys where date > (g.premier ?? "") && date < (g.dernier ?? "") { d.config.cycleMap[date] = 0 }
            }
            if gAnnee, let a = g.premier, let z = g.dernier {
                d.config.debut = a
                d.config.fin = z
                d.config.refDate = a
                d.config.refJour = g.cycle[a] ?? 1
                d.config.hebdo = false
                let maxJour = g.cycle.values.max() ?? d.config.cycleLen
                if maxJour >= 2 { d.config.cycleLen = maxJour }
            }
            if gSansEcole {
                // Regroupe les journées qui se suivent (ex. congé des Fêtes) en un seul événement
                let dates = g.sansEcole.keys.sorted()
                var i = 0
                while i < dates.count {
                    let debut = dates[i], type = g.sansEcole[debut] ?? .pedago, reprise = g.reprises.contains(debut)
                    var fin = debut
                    var j = i + 1
                    while j < dates.count, g.sansEcole[dates[j]] == type, g.reprises.contains(dates[j]) == reprise, prochainJourSemaine(fin) == dates[j] {
                        fin = dates[j]; j += 1
                    }
                    let titre = reprise ? "Journée pédagogique (reprise possible)" : (type == .conge ? "Congé" : "Journée pédagogique")
                    _ = store.ajouterSansEcole(titre, date: debut, fin: fin == debut ? "" : fin, type: type, dans: &d)
                    i = j
                }
            }
        }
        message = "Calendrier appliqué : les jours de cycle sont maintenant ceux de ton école."
        grille = nil
    }

    private func prochainJourSemaine(_ date: String) -> String {
        var x = D.add(date, 1)
        while D.weekday(x) == 0 || D.weekday(x) == 6 { x = D.add(x, 1) }
        return x
    }

    private func debut(_ t: String) { occupe = true; etat = t; message = nil; resultats = []; grille = nil }
    private func fin(_ m: String?) { occupe = false; message = m }
}

// MARK: - Texte d'une image (Vision, sur l'appareil)

enum LectureTexte {
    static func ocr(_ image: CGImage) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = true
                req.recognitionLanguages = ["fr-FR", "en-US"]
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([req])
                    let lignes = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lignes.joined(separator: "\n"))
                } catch {
                    cont.resume(returning: "")
                }
            }
        }
    }
}

// MARK: - Détection simple des dates (sans IA)

enum Heuristique {
    static let mois: [String: Int] = [
        "janvier": 1, "janv": 1, "février": 2, "fevrier": 2, "févr": 2, "fév": 2, "mars": 3, "avril": 4, "avr": 4,
        "mai": 5, "juin": 6, "juillet": 7, "juil": 7, "août": 8, "aout": 8, "septembre": 9, "sept": 9,
        "octobre": 10, "oct": 10, "novembre": 11, "nov": 11, "décembre": 12, "decembre": 12, "déc": 12, "dec": 12
    ]

    static func extraire(_ texte: String, config: Config) -> [Detecte] {
        let y1 = Int(config.debut.prefix(4)) ?? 2026
        let y2 = Int(config.fin.prefix(4)) ?? (y1 + 1)
        let motif = mois.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        guard let reDate = try? NSRegularExpression(pattern: "(\\d{1,2})(?:er)?\\s+(" + motif + ")\\.?(?:\\s+(\\d{4}))?", options: [.caseInsensitive]),
              let reISO = try? NSRegularExpression(pattern: "(\\d{4})-(\\d{2})-(\\d{2})"),
              let reHeure = try? NSRegularExpression(pattern: "\\b(\\d{1,2})\\s*h\\s*(\\d{2})?", options: [.caseInsensitive]),
              let reJour = try? NSRegularExpression(pattern: "\\b(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\\b", options: [.caseInsensitive])
        else { return [] }

        var out: [Detecte] = []
        var vus = Set<String>()
        for brute in texte.components(separatedBy: .newlines) {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            guard ligne.count >= 4 else { continue }
            let ns = ligne as NSString
            let tout = NSRange(location: 0, length: ns.length)
            var dates: [String] = []
            for m in reDate.matches(in: ligne, range: tout) {
                let j = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let nomMois = ns.substring(with: m.range(at: 2)).lowercased()
                guard let mo = mois[nomMois], (1...31).contains(j) else { continue }
                var an = mo >= 7 ? y1 : y2
                if m.range(at: 3).location != NSNotFound, let a = Int(ns.substring(with: m.range(at: 3))) { an = a }
                dates.append(String(format: "%04d-%02d-%02d", an, mo, j))
            }
            for m in reISO.matches(in: ligne, range: tout) { dates.append(ns.substring(with: m.range)) }
            guard let premiere = dates.first else { continue }

            let heures: [String] = reHeure.matches(in: ligne, range: tout).compactMap { m in
                let h = Int(ns.substring(with: m.range(at: 1))) ?? 99
                guard h < 24 else { return nil }
                let mi = m.range(at: 2).location != NSNotFound ? (Int(ns.substring(with: m.range(at: 2))) ?? 0) : 0
                return String(format: "%02d:%02d", h, mi)
            }

            var titre = reDate.stringByReplacingMatches(in: ligne, range: tout, withTemplate: "")
            titre = reISO.stringByReplacingMatches(in: titre, range: NSRange(location: 0, length: (titre as NSString).length), withTemplate: "")
            titre = reHeure.stringByReplacingMatches(in: titre, range: NSRange(location: 0, length: (titre as NSString).length), withTemplate: "")
            titre = reJour.stringByReplacingMatches(in: titre, range: NSRange(location: 0, length: (titre as NSString).length), withTemplate: "")
            titre = titre.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            titre = titre.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:,;.·|()•").union(.whitespaces))
            if titre.count < 2 { titre = "Événement" }

            let cle = premiere + titre.lowercased()
            guard !vus.contains(cle) else { continue }
            vus.insert(cle)
            let dateFin = dates.count > 1 && dates[1] > premiere ? dates[1] : ""
            out.append(Detecte(titre: String(titre.prefix(120)), date: premiere, dateFin: dateFin,
                               debut: heures.first ?? "", fin: heures.count > 1 ? heures[1] : "",
                               type: devinerType(ligne)))
        }
        return out
    }

    static func devinerType(_ t: String) -> TypeEvenement {
        let s = t.lowercased()
        func a(_ mots: [String]) -> Bool { mots.contains { s.contains($0) } }
        if a(["pédago", "pedago"]) { return .pedago }
        if a(["congé", "conge", "férié", "ferie", "relâche", "relache", "vacances", "fête du travail", "action de grâce", "noël"]) { return .conge }
        if a(["bulletin", "parents", "communication"]) { return .bulletin }
        if a(["conseil", "comité", "comite", "rencontre", "réunion", "reunion", "perfectionnement"]) { return .reunion }
        if a(["spectacle", "concert", "gala"]) { return .spectacle }
        if a(["sortie", "voyage"]) { return .sortie }
        if a(["examen", "évaluation", "evaluation"]) { return .cours }
        if a(["band", "pratique", "répétition", "repetition"]) { return .rdv }
        return .autre
    }
}
