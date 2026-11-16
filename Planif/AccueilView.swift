import SwiftUI

struct AccueilView: View {
    @EnvironmentObject var store: Store

    private let colonnes = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    entete
                    MaintenantCarte().padding(.horizontal, 16).offset(y: -40).padding(.bottom, -40)

                    if !store.data.config.hebdo && store.moteur.sansEcole.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tes jours de cycle peuvent être décalés.").bold()
                            Text("Ajoute tes journées pédagogiques et tes congés pour que le cycle soit exact.").font(.subheadline)
                            NavigationLink("Ajouter mes journées sans école") { SansEcoleView() }
                                .buttonStyle(.borderedProminent)
                        }
                        .carte().padding(.horizontal, 16)
                    }

                    LazyVGrid(columns: colonnes, spacing: 14) {
                        NavigationLink { GrilleView() } label: {
                            Tuile(icone: "square.grid.3x3", titre: "Horaire", sousTitre: "Grille du cycle de \(store.moteur.L) jours", miseEnAvant: true)
                        }
                        NavigationLink { EvenementsView() } label: {
                            Tuile(icone: "calendar.badge.plus", titre: "Événements", sousTitre: "Réunions, sorties, congés")
                        }
                        NavigationLink { SansEcoleView() } label: {
                            Tuile(icone: "sun.max", titre: "Sans école", sousTitre: "Pédagos et congés")
                        }
                        NavigationLink { ImportView() } label: {
                            Tuile(icone: "doc.viewfinder", titre: "Importer", sousTitre: "PDF ou photo → dates")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .background(Theme.fond)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var entete: some View {
        ZStack(alignment: .bottom) {
            Theme.vert
            Montagnes().fill(Color(hex: "3a5745")).frame(height: 60).opacity(0.9)
            Montagnes(decalage: 0.5).fill(Color(hex: "46664f")).frame(height: 40)
            HStack(spacing: 14) {
                Image(systemName: "calendar").font(.system(size: 44, weight: .light))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Planif").font(.system(size: 42, weight: .bold))
                    if !store.data.config.ecole.isEmpty {
                        Text(store.data.config.ecole).font(.subheadline).opacity(0.85)
                    }
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 74)
        }
        .frame(height: 230)
    }
}

struct Tuile: View {
    let icone: String
    let titre: String
    let sousTitre: String
    var miseEnAvant = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icone).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.vert).padding(.bottom, 8)
            Text(titre).font(.title3.bold()).foregroundStyle(.primary)
            Text(sousTitre).font(.footnote).foregroundStyle(Color(hex: "3c433e"))
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(miseEnAvant ? Theme.sauge : Theme.tuile, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct Montagnes: Shape {
    var decalage: CGFloat = 0
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts: [CGFloat] = decalage == 0 ? [0.55, 0.15, 0.5, 0.0, 0.45, 0.2, 0.55, 0.1, 0.4] : [0.6, 0.3, 0.55, 0.2, 0.6, 0.25, 0.5]
        p.move(to: CGPoint(x: 0, y: r.maxY))
        for (i, y) in pts.enumerated() {
            p.addLine(to: CGPoint(x: r.width * CGFloat(i) / CGFloat(pts.count - 1), y: r.minY + r.height * y))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
