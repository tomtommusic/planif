import SwiftUI

/// Configuration de départ : cycle, périodes, année scolaire et groupes.
struct AssistantView: View {
    @EnvironmentObject var store: Store
    @State private var config = Config(debut: "", fin: "", refDate: "")
    @State private var periodes: [Periode] = []
    @State private var groupesTexte = ""
    @State private var choixCycle = 9
    @State private var pret = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bienvenue dans Planif").font(.title2.bold())
                        Text("Configure ton horaire en une minute. Tout reste modifiable ensuite dans Plus → Réglages.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    TextField("Nom de l’école (optionnel)", text: $config.ecole)
                }
                ReglagesCycle(config: $config, choix: $choixCycle)
                ReglagesPeriodes(periodes: $periodes)
                Section("Année scolaire") {
                    DatePicker("Premier jour", selection: liaisonDate($config.debut), displayedComponents: .date)
                    DatePicker("Dernier jour", selection: liaisonDate($config.fin), displayedComponents: .date)
                    if !config.hebdo {
                        DatePicker("Une date connue", selection: liaisonDate($config.refDate), displayedComponents: .date)
                        Stepper("Son jour de cycle : \(config.refJour)", value: $config.refJour, in: 1...max(1, config.cycleLen))
                    }
                    Text("Planif compte les jours d’école à partir de cette date en sautant les fins de semaine, les congés et les journées pédagogiques.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    TextEditor(text: $groupesTexte).frame(minHeight: 120)
                } header: {
                    Text("Tes groupes, un par ligne")
                } footer: {
                    Text("Ex. : Groupe A (3e). Tu choisiras la couleur et l’icône de chacun ensuite.")
                }
                Section {
                    Button {
                        creer()
                    } label: {
                        Text("Créer mon horaire").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(periodes.isEmpty || config.fin < config.debut)
                }
            }
            .navigationTitle("Planif")
            .barreVerte()
        }
        .onAppear {
            guard !pret else { return }
            pret = true
            config = store.data.config
            periodes = store.data.periodes
            choixCycle = [5, 9, 10].contains(config.cycleLen) ? config.cycleLen : 0
            groupesTexte = store.data.groupes.map { $0.nom }.joined(separator: "\n")
        }
    }

    private func creer() {
        let noms = groupesTexte.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.maj { d in
            var c = config
            c.onboarded = true
            if c.refDate.isEmpty { c.refDate = c.debut }
            d.config = c
            d.periodes = periodes
            nettoyerGrille(&d)
            for n in noms where !d.groupes.contains(where: { $0.nom.lowercased() == n.lowercased() }) {
                store.nouveauGroupe(n, dans: &d)
            }
        }
    }
}

/// Retire de la grille les cases qui ne correspondent plus à un jour ou à une période.
func nettoyerGrille(_ d: inout AppData) {
    let ids = Set(d.periodes.map { $0.id })
    let L = d.config.cycleLen
    d.cellules = d.cellules.filter { cle, _ in
        let p = cle.split(separator: "|")
        guard p.count == 2, let j = Int(p[0]) else { return false }
        return j <= L && ids.contains(String(p[1]))
    }
    if d.config.refJour > L { d.config.refJour = 1 }
}

struct ReglagesCycle: View {
    @Binding var config: Config
    @Binding var choix: Int     // 5, 9, 10 ou 0 pour « autre »

    var body: some View {
        Section {
            Picker("Cycle", selection: $choix) {
                Text("5 jours").tag(5)
                Text("9 jours").tag(9)
                Text("10 jours").tag(10)
                Text("Autre").tag(0)
            }
            .pickerStyle(.segmented)
            .onChange(of: choix) { _, v in
                if v != 0 { config.cycleLen = v }
                if !(config.cycleLen == 5 || config.cycleLen == 10) { config.hebdo = false }
            }
            if choix == 0 {
                Stepper("Nombre de jours : \(config.cycleLen)", value: $config.cycleLen, in: 2...20)
            }
            if config.cycleLen == 5 || config.cycleLen == 10 {
                Toggle("Le cycle suit la semaine (le jour 1 est toujours un lundi)", isOn: $config.hebdo)
            }
        } header: {
            Text("Cycle de l’horaire")
        }
    }
}

struct ReglagesPeriodes: View {
    @Binding var periodes: [Periode]

    var body: some View {
        Section {
            ForEach($periodes) { $p in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nom", text: $p.nom).font(.body.bold())
                    HStack {
                        DatePicker("Début", selection: liaisonHeure($p.debut), displayedComponents: .hourAndMinute).labelsHidden()
                        Text("à")
                        DatePicker("Fin", selection: liaisonHeure($p.fin), displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }
            }
            .onDelete { periodes.remove(atOffsets: $0) }
            Button {
                let derniere = periodes.sorted { $0.debut < $1.debut }.last
                let debutMin = derniere.map { D.minutes($0.fin) + 10 } ?? 8 * 60
                let finMin = debutMin + 75
                periodes.append(Periode(nom: "Période \(periodes.count + 1)",
                                        debut: String(format: "%02d:%02d", (debutMin / 60) % 24, debutMin % 60),
                                        fin: String(format: "%02d:%02d", (finMin / 60) % 24, finMin % 60)))
            } label: {
                Label("Ajouter une période", systemImage: "plus")
            }
        } header: {
            Text("Périodes de la journée")
        } footer: {
            Text("Glisse une période vers la gauche pour la retirer.")
        }
    }
}
