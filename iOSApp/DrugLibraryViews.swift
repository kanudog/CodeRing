// DrugLibraryViews.swift — the editable drug system UI.
// Library → Set detail → Drug editor. Built-in sets duplicate instead of
// edit-in-place, so "PALS Default (Demo)" always survives as a reference.
// The editor's live preview card is the exact card language the watch uses:
// mL big, mg small — Examplitol exists to show this off.

import SwiftUI
import CodeCore

// MARK: - Library (sets)

struct DrugLibraryView: View {
    private let store = CodeStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.drugSets) { set in
                    NavigationLink {
                        DrugSetDetailView(setID: set.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name).font(.headline)
                                Text("\(set.drugs.count) drugs\(set.isBuiltIn ? " · built-in" : "")")
                                    .font(.caption)
                                    .foregroundStyle(CRTheme.textDim)
                            }
                            Spacer()
                            if store.settings.defaultDrugSetID == set.id {
                                Text("DEFAULT")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(CRTheme.rosc)
                            }
                        }
                    }
                    .swipeActions {
                        if !set.isBuiltIn {
                            Button(role: .destructive) {
                                store.delete(setID: set.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Drug Sets")
            .toolbar {
                Menu {
                    Button("New empty set") {
                        store.upsert(set: DrugProfileSet(name: "New Set", drugs: []))
                    }
                    Button("Duplicate PALS Default") {
                        var copy = Defaults.palsDrugSet
                        copy = DrugProfileSet(name: "PALS Copy",
                                              drugs: copy.drugs.map { d in
                                                  var nd = d
                                                  nd.id = UUID()   // new identities for the copy
                                                  return nd
                                              })
                        store.upsert(set: copy)
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Set detail

struct DrugSetDetailView: View {
    let setID: UUID
    private let store = CodeStore.shared
    @State private var renaming = false
    @State private var newName = ""

    private var set: DrugProfileSet? { store.drugSet(id: setID) }

    var body: some View {
        Group {
            if let set {
                List {
                    Section {
                        Toggle("Use for new codes", isOn: defaultBinding)
                        Button("Send all sets to Watch") {
                            ConnectivityManager.shared.send(.drugSets, store.drugSets)
                        }
                        if !set.isBuiltIn {
                            Button("Rename") {
                                newName = set.name
                                renaming = true
                            }
                        }
                    }

                    Section("Drugs") {
                        ForEach(set.drugs) { drug in
                            NavigationLink {
                                DrugEditorView(setID: setID, drugID: drug.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: drug.colorHex))
                                        .frame(width: 12, height: 12)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(drug.name).font(.body.weight(.semibold))
                                        Text(doseLine(drug))
                                            .font(.caption)
                                            .foregroundStyle(CRTheme.textDim)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    remove(drugID: drug.id)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        Button {
                            addDrug()
                        } label: {
                            Label("Add drug", systemImage: "plus")
                        }
                    }
                }
                .navigationTitle(set.name)
                .alert("Rename set", isPresented: $renaming) {
                    TextField("Name", text: $newName)
                    Button("Save") {
                        var s = set
                        s.name = newName
                        store.upsert(set: s)
                    }
                    Button("Cancel", role: .cancel) { }
                }
            } else {
                Text("Set deleted").foregroundStyle(CRTheme.textDim)
            }
        }
    }

    private var defaultBinding: Binding<Bool> {
        Binding(get: { store.settings.defaultDrugSetID == setID },
                set: { on in
                    var s = store.settings
                    s.defaultDrugSetID = on ? setID : nil
                    store.updateSettings(s)
                })
    }

    private func doseLine(_ drug: DrugProfile) -> String {
        let steps = drug.steps.map {
            "\(DoseCalculator.trim($0.perKg)) \(drug.unit.perKgSuffix)"
        }.joined(separator: " → ")
        return drug.subtitle.isEmpty ? steps : "\(steps) · \(drug.subtitle)"
    }

    private func addDrug() {
        guard var set else { return }
        let drug = DrugProfile(name: "New Drug",
                               steps: [DoseStep(label: "IV/IO", perKg: 0.1)],
                               concentrationMgPerMl: 1,
                               colorHex: CRTheme.customHex)
        set.drugs.append(drug)
        store.upsert(set: set)
    }

    private func remove(drugID: UUID) {
        guard var set else { return }
        set.drugs.removeAll { $0.id == drugID }
        store.upsert(set: set)
    }
}

// MARK: - Drug editor

struct DrugEditorView: View {
    let setID: UUID
    let drugID: UUID

    private let store = CodeStore.shared
    @State private var drug: DrugProfile?
    @State private var previewKg: Double = 10

    private let palette = ["FF3B5C", "F472B6", "FB923C", "FACC15",
                           "34D399", "2DD4BF", "38BDF8", "A78BFA", "F0ABFC"]

    var body: some View {
        Group {
            if drug != nil {
                Form {
                    Section {
                        previewCard
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Section("Identity") {
                        TextField("Name", text: bind(\.name))
                        TextField("Subtitle (concentration text)", text: bind(\.subtitle))
                        TextField("SF Symbol", text: bind(\.symbol))
                        Picker("Unit", selection: bind(\.unit)) {
                            Text("mg/kg").tag(DoseUnit.mgPerKg)
                            Text("J/kg (energy)").tag(DoseUnit.joulesPerKg)
                        }
                    }

                    Section("Color") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9)) {
                            ForEach(palette, id: \.self) { hex in
                                swatch(hex: hex)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Dose ladder") {
                        ForEach(stepIndices, id: \.self) { i in
                            stepRow(i)
                        }
                        .onDelete { offsets in drug?.steps.remove(atOffsets: offsets) }

                        Button {
                            drug?.steps.append(DoseStep(label: "Next", perKg: 0.1))
                        } label: {
                            Label("Add step", systemImage: "plus")
                        }
                    }

                    if drug?.unit == .mgPerKg {
                        Section {
                            HStack {
                                TextField("mg per mL", value: bind(\.concentrationMgPerMl),
                                          format: .number)
                                    .keyboardType(.decimalPad)
                                Text("mg/mL").foregroundStyle(CRTheme.textDim)
                            }
                        } header: {
                            Text("Concentration")
                        } footer: {
                            Text("Drives the featured mL number on the watch.")
                        }
                    }

                    Section {
                        Toggle("Resets interval timer", isOn: bind(\.resetsInterval))
                    } footer: {
                        Text("On for epinephrine: giving it restarts the epi countdown.")
                    }

                    Section("Notes") {
                        TextField("Notes", text: bind(\.notes), axis: .vertical)
                    }
                }
                .navigationTitle(drug?.name ?? "Drug")
                .toolbar {
                    Button("Save") { save() }.fontWeight(.bold)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            drug = store.drugSet(id: setID)?.drugs.first { $0.id == drugID }
        }
    }

    // The exact card style the watch renders — mL featured, mg secondary.
    private var previewCard: some View {
        VStack(spacing: 6) {
            HStack {
                CRIconView(symbol: drug?.symbol ?? "syringe", size: 17)
                    .foregroundStyle(Color(hex: drug?.colorHex ?? CRTheme.medHex))
                Text(drug?.name ?? "")
                    .font(.headline)
                    .foregroundStyle(CRTheme.text)
                Spacer()
                Stepper("", value: $previewKg, in: 1...60, step: 1)
                    .labelsHidden()
            }
            Text("Preview at \(DoseCalculator.trim(previewKg)) kg")
                .font(.caption2)
                .foregroundStyle(CRTheme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let d = drug {
                HStack(spacing: 10) {
                    ForEach(Array(DoseCalculator.doses(for: d, weightKg: previewKg).enumerated()),
                            id: \.offset) { _, result in
                        VStack(spacing: 0) {
                            Text(result.volumeText ?? result.amountText)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(hex: d.colorHex))
                            Text(result.volumeText != nil ? result.amountText : result.stepLabel)
                                .font(.caption)
                                .foregroundStyle(CRTheme.textDim)
                            if d.steps.count > 1 {
                                Text(result.stepLabel.uppercased())
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(CRTheme.textDim)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(CRTheme.surface))
    }

    // Same story as swatch(hex:): two format-inferring TextFields in one
    // row were too much for the type-checker inside the Form's closure.
    private func stepRow(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Step label", text: stepBind(i, \.label))
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("per kg", value: stepBind(i, \.perKg),
                          format: .number)
                    .keyboardType(.decimalPad)
                Text(drug?.unit.perKgSuffix ?? "")
                    .foregroundStyle(CRTheme.textDim)
                Divider()
                TextField("max", value: stepBind(i, \.maxAbsolute),
                          format: .number)
                    .keyboardType(.decimalPad)
                Text("max \(drug?.unit.amountSuffix ?? "")")
                    .foregroundStyle(CRTheme.textDim)
            }
            .font(.subheadline)
        }
    }

    // Kept out of the grid closure: the fill/overlay chain with an untyped
    // ternary line width blew past the type-checker's time budget inline.
    private func swatch(hex: String) -> some View {
        let ringWidth: CGFloat = drug?.colorHex == hex ? 2.5 : 0
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(.white, lineWidth: ringWidth))
            .onTapGesture { drug?.colorHex = hex }
    }

    private var stepIndices: Range<Int> {
        0..<(drug?.steps.count ?? 0)
    }

    private func bind<T>(_ keyPath: WritableKeyPath<DrugProfile, T>) -> Binding<T> {
        Binding(get: { drug![keyPath: keyPath] },
                set: { drug?[keyPath: keyPath] = $0 })
    }

    private func stepBind<T>(_ index: Int, _ keyPath: WritableKeyPath<DoseStep, T>) -> Binding<T> {
        Binding(get: { drug!.steps[index][keyPath: keyPath] },
                set: { drug?.steps[index][keyPath: keyPath] = $0 })
    }

    private func save() {
        guard var set = store.drugSet(id: setID), let drug else { return }
        if let idx = set.drugs.firstIndex(where: { $0.id == drugID }) {
            set.drugs[idx] = drug
        }
        store.upsert(set: set)
    }
}
