import SwiftUI

/// Consola de diagnóstico: muestra los comandos enviados, los mensajes
/// recibidos del ESP32 y los eventos de conexión.
struct ConsoleView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todo"
        case sent = "Enviados"
        case received = "Recibidos"
        var id: String { rawValue }
    }

    private var entries: [BluetoothManager.LogEntry] {
        switch filter {
        case .all:      return bluetooth.log
        case .sent:     return bluetooth.log.filter { $0.kind == .sent }
        case .received: return bluetooth.log.filter { $0.kind == .received }
        }
    }

    var body: some View {
        ZStack {
            Color.rtBackground.ignoresSafeArea()

            VStack(spacing: 12) {
                Picker("Filtro", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 32))
                            .foregroundColor(.rtTextSecondary)
                        Text("Sin actividad todavía")
                            .font(.system(size: 14))
                            .foregroundColor(.rtTextSecondary)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(entries) { entry in
                                    logRow(entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .onAppear {
                            if let last = entries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: bluetooth.log.count) { _ in
                            if let last = entries.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Consola")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    bluetooth.clearLog()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.rtDanger)
                }
                .disabled(bluetooth.log.isEmpty)
            }
        }
    }

    private func logRow(_ entry: BluetoothManager.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.rtTextSecondary.opacity(0.7))

            Image(systemName: icon(for: entry.kind))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color(for: entry.kind))
                .frame(width: 14)
                .padding(.top, 1)

            Text(entry.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(color(for: entry.kind))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func icon(for kind: BluetoothManager.LogEntry.Kind) -> String {
        switch kind {
        case .sent:     return "arrow.up"
        case .received: return "arrow.down"
        case .event:    return "info.circle"
        }
    }

    private func color(for kind: BluetoothManager.LogEntry.Kind) -> Color {
        switch kind {
        case .sent:     return .rtAccent
        case .received: return .rtSuccess
        case .event:    return .rtTextSecondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
