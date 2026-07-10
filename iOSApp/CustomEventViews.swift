// CustomEventViews.swift — build custom free events on the phone; they join
// the watch's Events bloom on next sync. Built-ins are shown read-only.

import SwiftUI
import CodeCore

struct EventsAdminView: View {
    private let store = CodeStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Send events to Watch") {
                        ConnectivityManager.shared.send(.customEvents, store.customEvents)
                    }
                }

                Section("Custom events") {
                    if store.customEvents.isEmpty {
                        Text("None yet — add one with +")
                            .foregroundStyle(CRTheme.textDim)
                    }
                    ForEach(store.customEvents) { event in
                        NavigationLink {
                            CustomEventEditor(eventID: event.id)
                        } label: {
                            eventRow(event)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.delete(eventID: event.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                Section("Built-in (read-only)") {
                    ForEach(Defaults.builtInEvents) { event in
                        eventRow(event)
                    }
                }
            }
            .navigationTitle("Events")
            .toolbar {
                NavigationLink {
                    CustomEventEditor(eventID: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func eventRow(_ event: EventDefinition) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.symbol)
                .foregroundStyle(event.category.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.body.weight(.semibold))
                Text(event.subOptions.isEmpty
                     ? event.category.label
                     : "\(event.category.label) · \(event.subOptions.count) options")
                    .font(.caption)
                    .foregroundStyle(CRTheme.textDim)
            }
        }
    }
}

struct CustomEventEditor: View {
    let eventID: String?     // nil = create

    private let store = CodeStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var symbol = "star.fill"
    @State private var category: EventCategory = .custom
    @State private var options: [String] = []

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                TextField("SF Symbol", text: $symbol)
                Picker("Category", selection: $category) {
                    ForEach(EventCategory.allCases, id: \.self) { c in
                        Text(c.label).tag(c)
                    }
                }
            }

            Section {
                ForEach(options.indices, id: \.self) { i in
                    TextField("Option \(i + 1)", text: $options[i])
                }
                .onDelete { options.remove(atOffsets: $0) }
                Button {
                    options.append("")
                } label: {
                    Label("Add sub-option", systemImage: "plus")
                }
            } header: {
                Text("Sub-options (optional)")
            } footer: {
                Text("Shows a second radial arc on the watch — releasing on the parent skips it and logs the generic event.")
            }

            Section {
                Button("Save") { save() }
                    .fontWeight(.bold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(eventID == nil ? "New Event" : "Edit Event")
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let eventID,
              let existing = store.customEvents.first(where: { $0.id == eventID })
        else { return }
        title = existing.title
        symbol = existing.symbol
        category = existing.category
        options = existing.subOptions
    }

    private func save() {
        let id = eventID ?? "custom.\(UUID().uuidString)"
        let cleaned = options
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let def = EventDefinition(id: id,
                                  title: title.trimmingCharacters(in: .whitespaces),
                                  category: category,
                                  symbol: symbol.isEmpty ? "star.fill" : symbol,
                                  subOptions: cleaned,
                                  isBuiltIn: false)
        store.upsert(event: def)
        dismiss()
    }
}
