import Foundation

// MARK: - Dates (format "AAAA-MM-JJ" et "HH:mm", comme la version web)

enum D {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "fr_CA")
        return c
    }()

    static func iso(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func date(_ s: String) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) ?? Date()
    }

    static func add(_ s: String, _ n: Int) -> String {
        iso(cal.date(byAdding: .day, value: n, to: date(s)) ?? Date())
    }

    /// 0 = dimanche … 6 = samedi
    static func weekday(_ s: String) -> Int { cal.component(.weekday, from: date(s)) - 1 }

    static func today() -> String { iso(Date()) }

    static func nowHM() -> String { hhmm(Date()) }

    static func hhmm(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func monday(_ s: String) -> String { add(s, -((weekday(s) + 6) % 7)) }

    static func minutes(_ t: String) -> Int {
        let p = t.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return 0 }
        return p[0] * 60 + p[1]
    }

    /// Date + heure "HH:mm" → Date
    static func dateTime(_ day: String, _ t: String) -> Date {
        let p = day.split(separator: "-").compactMap { Int($0) }
        let m = minutes(t)
        guard p.count == 3 else { return Date() }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: m / 60, minute: m % 60)) ?? Date()
    }

    /// "08:15" → "8h15"
    static func hm(_ t: String) -> String {
        guard !t.isEmpty else { return "" }
        var s = t.replacingOccurrences(of: ":", with: "h")
        if s.hasPrefix("0") && s.count > 4 { s.removeFirst() }
        return s
    }

    static func fmt(_ s: String, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = format
        let r = f.string(from: date(s))
        return r.prefix(1).uppercased() + r.dropFirst()
    }
    static func long(_ s: String) -> String { fmt(s, "EEEE d MMMM") }
    static func court(_ s: String) -> String { fmt(s, "EEE d MMM") }
    static func jm(_ s: String) -> String { fmt(s, "d MMM") }
    static func mois(_ s: String) -> String { fmt(s, "MMMM yyyy") }
    static let jourCourt = ["dim", "lun", "mar", "mer", "jeu", "ven", "sam"]
    static let jourLong = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
}

// MARK: - Éléments affichés

struct Plage: Hashable {
    let date: String
    let pid: String
    let debut: String
    let fin: String
}

struct Place: Hashable {
    let a: String       // id activité
    let k: Int          // rang dans l'activité (0…)
    let total: Int
    let si: Int         // index d'étape (-1 si aucune)
    let sk: Int
    let sn: Int
}

struct Portee {
    var slots: [Plage] = []
    var total: Int = 0
    var placees: Int { slots.count }
}

struct PlanTexte {
    let titre: String
    let etape: String
    let cours: String       // "Cours 2 sur 6"
    let etapePos: String    // "1/3"
}

enum TypeItem { case cours, libre, evenement }

struct ItemJour: Identifiable {
    let id: String
    let type: TypeItem
    let debut: String
    let fin: String
    var periode: Periode? = nil
    var groupe: Groupe? = nil
    var local: String = ""
    var cle: String = ""
    var annule: Bool = false
    var annuleParEvenement: Bool = false
    var place: Place? = nil
    var note: String = ""
    var evenement: Evenement? = nil
}

// MARK: - Moteur : cycle, événements, planification

final class Moteur {
    let d: AppData
    init(_ d: AppData) { self.d = d }

    var L: Int { max(1, min(20, d.config.cycleLen)) }

    func etiquetteJour(_ j: Int) -> String {
        if d.config.hebdo && L == 5, j >= 1, j <= 5 { return D.jourLong[j].prefix(1).uppercased() + D.jourLong[j].dropFirst() }
        if d.config.hebdo && L == 10 {
            let wd = (j - 1) % 5 + 1
            return (j <= 5 ? "Sem. A " : "Sem. B ") + D.jourCourt[wd]
        }
        return "Jour \(j)"
    }

    lazy var periodesTriees: [Periode] = d.periodes.sorted { $0.debut < $1.debut }
    lazy var groupesParId: [String: Groupe] = Dictionary(d.groupes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    lazy var activitesParId: [String: Activite] = Dictionary(d.activites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    private lazy var plagesSansEcole: [(String, String)] = d.evenements
        .filter { $0.type.sansEcole && $0.rec == .aucune }
        .map { ($0.date, $0.dateFin.isEmpty ? $0.date : $0.dateFin) }

    func sansEcoleParEvenement(_ date: String) -> Bool {
        plagesSansEcole.contains { date >= $0.0 && date <= $0.1 }
    }

    lazy var cycle: [String: Int] = calculerCycle()

    func jourCycle(_ date: String) -> Int? { cycle[date] }

    private func calculerCycle() -> [String: Int] {
        let c = d.config
        var map: [String: Int] = [:]
        guard c.debut.count == 10, c.fin.count == 10, c.debut <= c.fin else { return map }
        var list: [String] = []
        var x = c.debut
        var n = 0
        while x <= c.fin && n < 800 { list.append(x); x = D.add(x, 1); n += 1 }
        // 0 = pas d'école, -1 = jour d'école encore inconnu
        var vals = [Int](repeating: -1, count: list.count)
        let L = self.L

        if c.hebdo && (L == 5 || L == 10) {
            let refMon = D.date(D.monday(c.refDate.count == 10 ? c.refDate : c.debut))
            let base = c.refJour > 5 ? 1 : 0
            for (i, dt) in list.enumerated() {
                let wd = D.weekday(dt)
                if let ex = c.cycleMap[dt] { vals[i] = ex; continue }
                if wd == 0 || wd == 6 || sansEcoleParEvenement(dt) { vals[i] = 0; continue }
                if L == 5 { vals[i] = wd; continue }
                let semaines = Int((D.date(D.monday(dt)).timeIntervalSince(refMon) / 604800).rounded())
                let moitie = (((base + semaines) % 2) + 2) % 2
                vals[i] = moitie * 5 + wd
            }
        } else {
            var cur = -1
            var first = -1
            for (i, dt) in list.enumerated() {
                let wd = D.weekday(dt)
                if let ex = c.cycleMap[dt] {
                    if ex == 0 { vals[i] = 0; continue }
                    cur = ex; vals[i] = ex
                    if first < 0 { first = i }
                    continue
                }
                if wd == 0 || wd == 6 || sansEcoleParEvenement(dt) { vals[i] = 0; continue }
                if dt == c.refDate {
                    cur = min(L, max(1, c.refJour)); vals[i] = cur
                    if first < 0 { first = i }
                    continue
                }
                if cur > 0 { cur = cur % L + 1; vals[i] = cur }
            }
            if first > 0 {
                var k = vals[first]
                var i = first - 1
                while i >= 0 {
                    if vals[i] != 0 { k = (k - 2 + L) % L + 1; vals[i] = k }
                    i -= 1
                }
            }
        }
        for (i, dt) in list.enumerated() where vals[i] > 0 { map[dt] = vals[i] }
        return map
    }

    func prochainJourEcole(apres date: String) -> String? {
        var x = date
        for _ in 0..<90 {
            x = D.add(x, 1)
            if jourCycle(x) != nil { return x }
        }
        return nil
    }

    // MARK: Événements

    func evenementLe(_ e: Evenement, _ date: String, _ cd: Int?) -> Bool {
        switch e.rec {
        case .aucune:
            return date >= e.date && date <= (e.dateFin.isEmpty ? e.date : e.dateFin)
        case .hebdo:
            if date < e.date || (!e.jusquau.isEmpty && date > e.jusquau) || e.exceptions.contains(date) { return false }
            return e.jours.contains(D.weekday(date)) && (!e.ecoleSeulement || cd != nil)
        case .cycle:
            if date < e.date || (!e.jusquau.isEmpty && date > e.jusquau) || e.exceptions.contains(date) { return false }
            guard let cd else { return false }
            return e.jours.contains(cd)
        }
    }

    func evenements(_ date: String) -> [Evenement] {
        let cd = jourCycle(date)
        return d.evenements.filter { evenementLe($0, date, cd) }
    }

    func coursAnnulesLe(_ date: String) -> Bool {
        evenements(date).contains { $0.annuleCours }
    }

    var sansEcole: [Evenement] {
        d.evenements.filter { $0.type.sansEcole && $0.rec == .aucune }.sorted { $0.date < $1.date }
    }

    // MARK: Plages de chaque groupe

    lazy var plagesParGroupe: [String: [Plage]] = {
        var out: [String: [Plage]] = [:]
        let per = self.periodesTriees
        let cyc = self.cycle
        let cells = self.d.cellules
        for date in cyc.keys.sorted() {
            guard let cd = cyc[date] else { continue }
            for p in per {
                if let c = cells["\(cd)|\(p.id)"] {
                    out[c.g, default: []].append(Plage(date: date, pid: p.id, debut: p.debut, fin: p.fin))
                }
            }
        }
        return out
    }()

    static func cle(_ gid: String, _ date: String, _ pid: String) -> String { "\(gid)|\(date)|\(pid)" }

    // MARK: Planification : les activités coulent dans les périodes, dans l'ordre de la liste

    func sequence(_ a: Activite) -> [(si: Int, sk: Int, sn: Int)] {
        let etapes = a.etapes.filter { $0.periodes > 0 }
        var seq: [(si: Int, sk: Int, sn: Int)] = []
        if !etapes.isEmpty {
            for (si, s) in etapes.enumerated() { for k in 0..<s.periodes { seq.append((si, k, s.periodes)) } }
        } else {
            let n = max(0, a.nbPeriodes)
            for k in 0..<n { seq.append((-1, k, n)) }
        }
        return seq
    }

    lazy var plan: (places: [String: Place], portees: [String: Portee]) = {
        var places: [String: Place] = [:]
        var portees: [String: Portee] = [:]
        let annul = Set(self.d.annulations)
        var annulJour: [String: Bool] = [:]
        let pg = self.plagesParGroupe
        for g in self.d.groupes {
            var slots: [Plage] = []
            for s in pg[g.id] ?? [] {
                if annul.contains(Moteur.cle(g.id, s.date, s.pid)) { continue }
                if annulJour[s.date] == nil { annulJour[s.date] = self.coursAnnulesLe(s.date) }
                if annulJour[s.date] == true { continue }
                slots.append(s)
            }
            var i = 0
            for a in self.d.activites where a.groupes.contains(g.id) {
                let seq = self.sequence(a)
                while i < slots.count && slots[i].date < a.debut { i += 1 }
                var r = Portee(slots: [], total: seq.count)
                var k = 0
                while k < seq.count && i < slots.count {
                    let s = slots[i]
                    places[Moteur.cle(g.id, s.date, s.pid)] = Place(a: a.id, k: k, total: seq.count, si: seq[k].si, sk: seq[k].sk, sn: seq[k].sn)
                    r.slots.append(s)
                    k += 1; i += 1
                }
                portees[a.id + "|" + g.id] = r
            }
        }
        return (places, portees)
    }()

    func texte(_ p: Place?) -> PlanTexte? {
        guard let p, let a = activitesParId[p.a] else { return nil }
        let etapes = a.etapes.filter { $0.periodes > 0 }
        let et = p.si >= 0 && p.si < etapes.count ? etapes[p.si] : nil
        let n = p.k + 1
        let cours = p.total > 1 ? "Cours \(n) sur \(p.total)" + (n == p.total ? " · dernier" : "") : "Cours unique"
        return PlanTexte(titre: a.titre, etape: et?.titre ?? "", cours: cours, etapePos: et != nil ? "\(p.sk + 1)/\(p.sn)" : "")
    }

    // MARK: Journée

    func items(_ date: String) -> [ItemJour] {
        let cd = jourCycle(date)
        var out: [ItemJour] = []
        let annulJour = coursAnnulesLe(date)
        let annul = Set(d.annulations)
        for e in evenements(date) {
            out.append(ItemJour(id: "e" + e.id, type: .evenement, debut: e.journee ? "" : e.debut, fin: e.journee ? "" : e.fin, evenement: e))
        }
        if let cd {
            for p in periodesTriees {
                if let c = d.cellules["\(cd)|\(p.id)"], let g = groupesParId[c.g] {
                    let k = Moteur.cle(g.id, date, p.id)
                    out.append(ItemJour(id: k, type: .cours, debut: p.debut, fin: p.fin, periode: p, groupe: g,
                                        local: c.local.isEmpty ? g.local : c.local, cle: k,
                                        annule: annul.contains(k) || annulJour, annuleParEvenement: annulJour,
                                        place: plan.places[k], note: d.notes[k] ?? ""))
                } else {
                    out.append(ItemJour(id: "f" + date + p.id, type: .libre, debut: p.debut, fin: p.fin, periode: p))
                }
            }
        }
        out.sort { a, b in
            if a.debut != b.debut { return a.debut < b.debut }
            return a.type == .evenement && b.type != .evenement
        }
        return out
    }

    // MARK: Statistiques d'une activité

    struct Stats { var total = 0; var faites = 0; var premier: String? = nil; var dernier: String? = nil; var jours = 0; var manquantes = 0 }

    func stats(_ a: Activite, maintenant: Date = Date()) -> Stats {
        var s = Stats()
        let t = D.iso(maintenant), h = D.hhmm(maintenant)
        var dates = Set<String>()
        for gid in a.groupes {
            guard let r = plan.portees[a.id + "|" + gid] else { continue }
            s.total += r.total
            s.manquantes += r.total - r.placees
            for p in r.slots {
                dates.insert(p.date)
                if p.date < t || (p.date == t && p.fin <= h) { s.faites += 1 }
                if s.premier == nil || p.date < s.premier! { s.premier = p.date }
                if s.dernier == nil || p.date > s.dernier! { s.dernier = p.date }
            }
        }
        s.jours = dates.count
        return s
    }

    // MARK: Congés fériés du Québec pour l'année scolaire

    static func paques(_ y: Int) -> String {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let mo = (h + l - 7 * m + 114) / 31, da = ((h + l - 7 * m + 114) % 31) + 1
        return String(format: "%04d-%02d-%02d", y, mo, da)
    }

    static func nLundi(_ y: Int, _ mois: Int, _ n: Int) -> String {
        var x = String(format: "%04d-%02d-01", y, mois)
        while D.weekday(x) != 1 { x = D.add(x, 1) }
        return D.add(x, 7 * (n - 1))
    }

    func feriesQuebec() -> [(String, String)] {
        let y1 = Int(d.config.debut.prefix(4)) ?? 2026, y2 = Int(d.config.fin.prefix(4)) ?? 2027
        var out: [(String, String)] = []
        for y in Set([y1, y2]).sorted() {
            let p = Moteur.paques(y)
            var pat = String(format: "%04d-05-24", y)
            while D.weekday(pat) != 1 { pat = D.add(pat, -1) }
            out += [("Fête du Travail", Moteur.nLundi(y, 9, 1)), ("Action de grâce", Moteur.nLundi(y, 10, 2)),
                    ("Vendredi saint", D.add(p, -2)), ("Lundi de Pâques", D.add(p, 1)), ("Journée nationale des patriotes", pat)]
        }
        return out.filter { $0.1 >= d.config.debut && $0.1 <= d.config.fin }
    }
}
