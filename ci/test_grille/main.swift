import Foundation
import PDFKit

// Test hors app : lit le calendrier scolaire de démonstration avec le même code que l'app.
let chemin = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ci/fixtures/calendrier-sommets-2026-2027.pdf"
guard let doc = PDFDocument(url: URL(fileURLWithPath: chemin)) else { print("PDF illisible"); exit(1) }
GrilleCalendrier.journal = { print("  · " + $0) }
var g = ResultatGrille()
for i in 0..<doc.pageCount { if let p = doc.page(at: i) { g.fusionner(GrilleCalendrier.analyser(p)) } }
print("jours de cycle :", g.cycle.count, "du", g.premier ?? "-", "au", g.dernier ?? "-")
print("pédagos :", g.nbPedago, " congés :", g.nbConge, " reprises :", g.reprises.sorted())
for d in g.sansEcole.keys.sorted() { print("  sans école", d, g.sansEcole[d]!.rawValue) }
if let a = g.premier, let z = g.dernier {
    var x = a; var prec: Int? = nil
    while x <= z {
        let wd = D.weekday(x)
        if let j = g.cycle[x] {
            if wd == 0 || wd == 6 { print("  fin de semaine avec cycle", x, j) }
            if let p = prec, j != p % 9 + 1 { print("  saut", x, p, "→", j) }
            prec = j
        } else if wd >= 1 && wd <= 5 && g.sansEcole[x] == nil { print("  jour sans info", x) }
        x = D.add(x, 1)
    }
}
var ok = true
func verifier(_ d: String, _ j: Int) { if g.cycle[d] != j { print("ÉCHEC", d, "attendu", j, "obtenu", g.cycle[d] as Any); ok = false } }
verifier("2026-08-25", 1); verifier("2026-08-26", 2); verifier("2026-09-08", 1); verifier("2026-11-17", 2); verifier("2027-06-21", 9)
if g.cycle.count != 180 { print("ÉCHEC : 180 jours attendus"); ok = false }
if g.sansEcole["2026-09-18"] != .pedago { print("ÉCHEC : 18 sept. devrait être pédago"); ok = false }
if g.sansEcole["2026-12-24"] != .conge { print("ÉCHEC : 24 déc. devrait être congé"); ok = false }
print(ok ? "TEST GRILLE : OK" : "TEST GRILLE : ÉCHEC")
exit(ok ? 0 : 1)
