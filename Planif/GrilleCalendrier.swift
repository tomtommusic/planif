import Foundation
import PDFKit
import CoreGraphics

/// Résultat de la lecture d'un calendrier scolaire en grille (un mois par case, jours de cycle en indice).
struct ResultatGrille {
    var cycle: [String: Int] = [:]                 // date → jour de cycle
    var sansEcole: [String: TypeEvenement] = [:]    // date → pédago ou congé (d'après la couleur de la case)
    var reprises: Set<String> = []                  // journées de reprise possible (triangle orange)
    var premier: String? { cycle.keys.min() }
    var dernier: String? { cycle.keys.max() }
    var nbPedago: Int { sansEcole.values.filter { $0 == .pedago }.count }
    var nbConge: Int { sansEcole.values.filter { $0 == .conge }.count }

    mutating func fusionner(_ r: ResultatGrille) {
        cycle.merge(r.cycle) { a, _ in a }
        sansEcole.merge(r.sansEcole) { a, _ in a }
        reprises.formUnion(r.reprises)
    }
}

/// Lit la position de chaque chiffre dans le PDF : les grands chiffres sont les dates,
/// les petits chiffres en indice sont les jours de cycle. La couleur de la case indique
/// les journées pédagogiques (bleu), les congés (vert) et les reprises possibles (orange).
enum GrilleCalendrier {
    private struct Jeton {
        var t: String
        var x0: CGFloat, x1: CGFloat, top: CGFloat, bottom: CGFloat
        var h: CGFloat { bottom - top }
        var date: String? = nil
    }
    private struct Entete {
        let m: Int, y: Int
        let x0: CGFloat, x1: CGFloat, top: CGFloat, bottom: CGFloat
    }

    /// Pour les tests : reçoit des détails sur la lecture.
    static var journal: ((String) -> Void)? = nil

    static let mois: [String: Int] = [
        "JANVIER": 1, "FÉVRIER": 2, "FEVRIER": 2, "MARS": 3, "AVRIL": 4, "MAI": 5, "JUIN": 6, "JUILLET": 7,
        "AOÛT": 8, "AOUT": 8, "SEPTEMBRE": 9, "OCTOBRE": 10, "NOVEMBRE": 11, "DÉCEMBRE": 12, "DECEMBRE": 12
    ]

    static func analyser(_ page: PDFPage) -> ResultatGrille {
        var res = ResultatGrille()
        guard let s = page.string, !s.isEmpty else { return res }
        let ns = s as NSString
        let box = page.bounds(for: .mediaBox)

        // Coordonnées « du haut vers le bas » (comme une image)
        func conv(_ r: CGRect) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            (r.minX - box.minX, r.maxX - box.minX, box.maxY - r.maxY, box.maxY - r.minY)
        }

        // Position d'un caractère (via une sélection : même numérotation que page.string)
        func boite(_ i: Int) -> CGRect {
            guard let sel = page.selection(for: NSRange(location: i, length: 1)) else { return .zero }
            return sel.bounds(for: page)
        }

        // 1. Chiffres avec leur position, regroupés en nombres
        var chiffres: [Jeton] = []
        for i in 0..<ns.length {
            let c = ns.character(at: i)
            guard c >= 48 && c <= 57 else { continue }
            let r = boite(i)
            guard r.width > 0, r.height > 0 else { continue }
            let (x0, x1, top, bottom) = conv(r)
            chiffres.append(Jeton(t: String(Character(UnicodeScalar(UInt8(c)))), x0: x0, x1: x1, top: top, bottom: bottom))
        }
        chiffres.sort { a, b in
            let ya = a.bottom.rounded(), yb = b.bottom.rounded()
            return ya != yb ? ya < yb : a.x0 < b.x0
        }
        var jetons: [Jeton] = []
        for c in chiffres {
            if var cur = jetons.last {
                let ecart = c.x0 - cur.x1
                if abs(c.h - cur.h) < 0.25 * cur.h && abs(c.bottom - cur.bottom) < 0.3 * c.h && ecart >= -0.4 * c.h && ecart < 0.25 * c.h {
                    cur.t += c.t
                    cur.x1 = c.x1
                    jetons[jetons.count - 1] = cur
                    continue
                }
            }
            jetons.append(c)
        }

        // 2. En-têtes de mois (« SEPTEMBRE 2026 »)
        guard let re = try? NSRegularExpression(pattern: "(JANVIER|FÉVRIER|FEVRIER|MARS|AVRIL|MAI|JUIN|JUILLET|AOÛT|AOUT|SEPTEMBRE|OCTOBRE|NOVEMBRE|DÉCEMBRE|DECEMBRE)\\s*(\\d{4})", options: [.caseInsensitive]) else { return res }
        var entetes: [Entete] = []
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            var x0 = CGFloat.greatestFiniteMagnitude, x1 = -CGFloat.greatestFiniteMagnitude
            var top = CGFloat.greatestFiniteMagnitude, bottom = -CGFloat.greatestFiniteMagnitude
            for i in m.range.location..<(m.range.location + m.range.length) {
                let r = boite(i)
                guard r.width > 0, r.height > 0 else { continue }
                let v = conv(r)
                x0 = min(x0, v.0); x1 = max(x1, v.1); top = min(top, v.2); bottom = max(bottom, v.3)
            }
            guard x0 < x1 else { continue }
            let nom = ns.substring(with: m.range(at: 1)).uppercased()
            guard let mo = mois[nom], let an = Int(ns.substring(with: m.range(at: 2))) else { continue }
            entetes.append(Entete(m: mo, y: an, x0: x0, x1: x1, top: top, bottom: bottom))
        }
        let candidats = jetons.filter { (Int($0.t) ?? 0) >= 1 && (Int($0.t) ?? 0) <= 31 }
        journal?("caractères \(ns.length), chiffres \(chiffres.count), nombres \(jetons.count), en-têtes \(entetes.count), candidats \(candidats.count)")
        journal?("exemples : " + jetons.prefix(12).map { "\($0.t)@(\(Int($0.x0)),\(Int($0.top)) h\(Int($0.h)))" }.joined(separator: " "))
        journal?("en-têtes : " + entetes.map { "\($0.m)/\($0.y)@(\(Int($0.x0)),\(Int($0.top)))" }.joined(separator: " "))
        guard entetes.count >= 2, candidats.count >= 28 else { return res }

        let hauteurs = candidats.map { $0.h }.sorted()
        let H = hauteurs[hauteurs.count / 2]
        var grands = candidats.filter { $0.h >= 0.8 * H }
        let petits = jetons.filter { $0.h < 0.75 * H && $0.t.count == 1 && $0.t != "0" }
        journal?("H \(H), grands \(grands.count), petits \(petits.count)")

        // Largeur d'une colonne de mois
        let centres = entetes.map { ($0.x0 + $0.x1) / 2 }.sorted()
        var W = box.width / 4
        var ecarts: [CGFloat] = []
        for i in 1..<centres.count where centres[i] - centres[i - 1] > 20 { ecarts.append(centres[i] - centres[i - 1]) }
        if let mn = ecarts.min() { W = mn }

        // 3. Chaque grand chiffre appartient au mois dont l'en-tête est juste au-dessus, dans la même colonne
        var parDate: [String: Jeton] = [:]
        for i in grands.indices {
            let t = grands[i]
            let mx = (t.x0 + t.x1) / 2
            var meilleur: (CGFloat, Entete)? = nil
            for e in entetes {
                guard abs(mx - (e.x0 + e.x1) / 2) <= W / 2 else { continue }
                let d = t.top - e.bottom
                if d > 0 && d < 12 * H && (meilleur == nil || d < meilleur!.0) { meilleur = (d, e) }
            }
            guard let e = meilleur?.1, let j = Int(t.t) else { continue }
            let iso = String(format: "%04d-%02d-%02d", e.y, e.m, j)
            guard D.iso(D.date(iso)) == iso else { continue }
            grands[i].date = iso
            if parDate[iso] == nil { parDate[iso] = grands[i] }
        }

        // 4. Petits chiffres en indice, en bas à droite d'une date = jour de cycle
        for p in petits {
            var meilleur: (CGFloat, String)? = nil
            for b in grands {
                guard let date = b.date else { continue }
                let dx = p.x0 - b.x1
                guard dx >= -0.3 * b.h, dx < 1.2 * b.h, p.bottom > b.bottom - 0.2 * b.h, p.top > b.top, p.top < b.bottom + 0.3 * b.h else { continue }
                let dist = dx * dx + (p.bottom - b.bottom) * (p.bottom - b.bottom)
                if meilleur == nil || dist < meilleur!.0 { meilleur = (dist, date) }
            }
            if let m = meilleur, let v = Int(p.t) { res.cycle[m.1] = v }
        }
        journal?("dates \(parDate.count), jours de cycle \(res.cycle.count)")
        guard res.cycle.count >= 10, let premier = res.premier, let dernier = res.dernier else { return ResultatGrille() }

        // 5. Jours de semaine sans jour de cycle : pas d'école. La couleur de la case dit pédago ou congé.
        let image = Rendu(page: page, echelle: 2)
        for (date, j) in parDate {
            let wd = D.weekday(date)
            guard wd >= 1 && wd <= 5, res.cycle[date] == nil else { continue }
            let couleur = image?.classer(x0: j.x0 - 0.35 * j.h, x1: j.x1 + 0.35 * j.h, top: j.top + 0.1 * j.h, bottom: j.bottom - 0.1 * j.h)
            let dansAnnee = date > premier && date < dernier
            switch couleur {
            case "pedago": res.sansEcole[date] = .pedago
            case "conge": res.sansEcole[date] = .conge
            case "reprise": res.sansEcole[date] = .pedago; res.reprises.insert(date)
            default: if dansAnnee { res.sansEcole[date] = .pedago }
            }
        }
        return res
    }

    /// Image de la page pour lire la couleur des cases.
    private final class Rendu {
        let w: Int, h: Int, echelle: CGFloat, box: CGRect
        var pixels: [UInt8]

        init?(page: PDFPage, echelle: CGFloat) {
            box = page.bounds(for: .mediaBox)
            self.echelle = echelle
            w = Int(box.width * echelle); h = Int(box.height * echelle)
            guard w > 0, h > 0, w * h < 40_000_000 else { return nil }
            pixels = [UInt8](repeating: 255, count: w * h * 4)
            let ok: Bool = pixels.withUnsafeMutableBytes { ptr -> Bool in
                guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.scaleBy(x: echelle, y: echelle)
                ctx.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .mediaBox, to: ctx)
                return true
            }
            if !ok { return nil }
        }

        /// Compte les pixels bleus, verts et orange dans la case (coordonnées du haut vers le bas, en points).
        func classer(x0: CGFloat, x1: CGFloat, top: CGFloat, bottom: CGFloat) -> String? {
            var n = ["pedago": 0, "conge": 0, "reprise": 0]
            let px0 = max(0, Int(x0 * echelle)), px1 = min(w - 1, Int(x1 * echelle))
            let py0 = max(0, Int(top * echelle)), py1 = min(h - 1, Int(bottom * echelle))
            guard px0 < px1, py0 < py1 else { return nil }
            var y = py0
            while y <= py1 {
                var x = px0
                while x <= px1 {
                    let i = (y * w + x) * 4
                    let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                    if b > r + 60 && b > 150 && g > 150 { n["pedago", default: 0] += 1 }
                    else if g > r + 20 && g > b + 20 && g > 140 { n["conge", default: 0] += 1 }
                    else if r > 200 && g > 110 && g < 200 && b < 90 { n["reprise", default: 0] += 1 }
                    x += 2
                }
                y += 2
            }
            guard let top = n.max(by: { $0.value < $1.value }), top.value > 3 else { return nil }
            return top.key
        }
    }
}
