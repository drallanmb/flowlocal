import SwiftUI
import AppKit
import AVFoundation
import ServiceManagement

struct HubView: View {
    @EnvironmentObject var nav: HubNav

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 188)
            Divider().opacity(0.5)
            Group {
                switch nav.page {
                case .history: HomePage()
                case .dictionary: DictionaryPage()
                case .snippets: SnippetsPage()
                case .style: StylePage()
                case .scratchpad: ScratchpadPage()
                case .settings: SettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

// MARK: - Local state

/// The Command Line Tools toolchain ships without the SwiftUIMacros plugin that `@State` now needs,
/// so views use this equivalent, built on `@StateObject`.
final class StateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

@propertyWrapper
struct LState<Value>: DynamicProperty {
    @StateObject private var box: StateBox<Value>
    init(wrappedValue: Value) { _box = StateObject(wrappedValue: StateBox(wrappedValue)) }
    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<Value> { Binding(get: { box.value }, set: { box.value = $0 }) }
}

// MARK: - Shared pieces

private struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

private struct EmptyHint: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject var nav: HubNav

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarIcon.image(arcs: 3, size: 22))
                    .renderingMode(.template)
                Text("FlowLocal").font(.system(size: 14, weight: .semibold))
            }
            .padding(.top, 38).padding(.bottom, 20).padding(.horizontal, 10)

            ForEach(HubPage.allCases.filter { $0 != .settings }) { row($0) }
            Spacer()
            row(.settings).padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func row(_ page: HubPage) -> some View {
        let selected = nav.page == page
        return Button { nav.page = page } label: {
            HStack(spacing: 9) {
                Image(systemName: page.symbol).font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Text(page.title).font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.primary.opacity(0.08) : .clear))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permission guide (one step at a time)

private struct PermissionGuide: View {
    @ObservedObject private var model = PermissionsModel.shared

    var body: some View {
        if let step = model.currentStep {
            let steps = Permission.guideSteps
            let index = (steps.firstIndex(of: step) ?? 0) + 1
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuração inicial · passo \(index) de \(steps.count)")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        ForEach(steps) { p in
                            let done = model.granted[p] == true
                            HStack(spacing: 5) {
                                Image(systemName: done ? "checkmark.circle.fill" : (p == step ? "circle.inset.filled" : "circle"))
                                    .foregroundStyle(done ? Color.green : (p == step ? Color.accentColor : Color.secondary))
                                Text(p.title).font(.caption)
                                    .foregroundStyle(p == step ? Color.primary : Color.secondary)
                            }
                        }
                    }

                    Text(step.title).font(.headline)
                    Text(step.why).font(.callout).foregroundStyle(.secondary)
                    Text(instructions(for: step))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button("Abrir ajustes: \(step.title)") { step.request() }
                            .buttonStyle(.borderedProminent)
                        Label("Aguardando você ativar…", systemImage: "hourglass")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func instructions(for step: Permission) -> String {
        var text = "1. Clique no botão abaixo.\n2. Em \(step.pane), ligue o interruptor de “FlowLocal”.\n3. Volte aqui: o passo é marcado ✓ sozinho assim que o macOS confirmar."
        if step == .microphone && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            text = "1. Clique no botão abaixo: o macOS vai mostrar um aviso.\n2. Clique em “Permitir”.\n3. Este passo é marcado ✓ sozinho."
        }
        if step == .screenRecording { text += "\nO macOS pode pedir para reabrir o FlowLocal; aceite." }
        return text
    }
}

// MARK: - Home (history)

private struct HomePage: View {
    @StateObject private var store = HistoryStore()
    @LState private var query = ""
    @LState private var confirmClear = false

    private var filtered: [HistoryEntry] {
        query.isEmpty ? store.entries : store.entries.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.app.localizedCaseInsensitiveContains(query)
        }
    }

    private var groups: [(String, [HistoryEntry])] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        var out: [(String, [HistoryEntry])] = []
        for e in filtered {
            let title = cal.isDateInToday(e.at) ? "Hoje" : cal.isDateInYesterday(e.at) ? "Ontem" : f.string(from: e.at).capitalized
            if let i = out.firstIndex(where: { $0.0 == title }) { out[i].1.append(e) } else { out.append((title, [e])) }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Início", subtitle: "Segure \(Settings.hotkey.title), fale e solte.")
                    .padding(.top, 32)

                PermissionGuide()

                Text("\(store.entries.count) ditados  ·  \(store.totalWords) palavras  ·  \(store.wpm) palavras/min")
                    .font(.footnote).foregroundStyle(.tertiary)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar no histórico", text: $query).textFieldStyle(.plain)
                    if !store.entries.isEmpty {
                        Button("Limpar tudo", role: .destructive) { confirmClear = true }.buttonStyle(.link)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

                if filtered.isEmpty {
                    EmptyHint(symbol: "waveform", text: store.entries.isEmpty
                              ? "Nada por aqui ainda. Faça seu primeiro ditado!"
                              : "Nenhum resultado para “\(query)”.")
                }
                ForEach(groups, id: \.0) { title, entries in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                        VStack(spacing: 0) {
                            ForEach(entries) { e in
                                HistoryRow(entry: e, onDelete: { store.delete(e.id) })
                                if e.id != entries.last?.id { Divider().opacity(0.5).padding(.vertical, 10) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Apagar todo o histórico?", isPresented: $confirmClear) {
            Button("Apagar tudo", role: .destructive) { store.clear() }
        } message: { Text("Isso não pode ser desfeito.") }
    }

}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void
    @LState private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.at, style: .time)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if entry.isCommand {
                    Label("Comando: “\(entry.raw)”", systemImage: "wand.and.stars")
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
                if !entry.app.isEmpty {
                    Text("\(entry.app) · \(entry.words) palavras").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.borderless).help("Copiar")
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Apagar")
        }
    }
}

// MARK: - Dictionary

private struct DictionaryPage: View {
    @StateObject private var store = DictionaryStore()
    @LState private var from = ""
    @LState private var to = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Dicionário",
                           subtitle: "Nomes, siglas e termos que o FlowLocal deve escrever do seu jeito. Eles também orientam o reconhecimento de voz.")
                    .padding(.top, 32)

                Card {
                    HStack(spacing: 8) {
                        TextField("Palavra ou como você fala", text: $from).textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Escrever como (opcional)", text: $to).textFieldStyle(.roundedBorder)
                        Button("Adicionar") { store.add(from: from, to: to); from = ""; to = "" }
                            .keyboardShortcut(.defaultAction)
                            .disabled(from.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if store.items.isEmpty {
                    EmptyHint(symbol: "character.book.closed", text: "Sem palavras ainda. Ex.: “claude code” → “Claude Code”.")
                } else {
                    Card {
                        VStack(spacing: 8) {
                            ForEach($store.items) { $item in
                                HStack(spacing: 8) {
                                    TextField("", text: $item.from).textFieldStyle(.roundedBorder)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    TextField("", text: $item.to).textFieldStyle(.roundedBorder)
                                    Button { store.remove(item.id) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .onChange(of: store.items) { _ in store.save() }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Snippets

private struct SnippetsPage: View {
    @StateObject private var store = SnippetStore()
    @LState private var trigger = ""
    @LState private var expansion = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Snippets",
                           subtitle: "Diga uma frase curta e o FlowLocal cola o texto completo. O texto do snippet é inserido exatamente como escrito.")
                    .padding(.top, 32)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Quando eu disser… (ex.: meu linkedin)", text: $trigger).textFieldStyle(.roundedBorder)
                        TextEditor(text: $expansion)
                            .font(.body).frame(height: 84)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                        HStack {
                            Text("Escreva…").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Adicionar snippet") { store.add(trigger: trigger, expansion: expansion); trigger = ""; expansion = "" }
                                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
                        }
                    }
                }

                if store.items.isEmpty {
                    EmptyHint(symbol: "text.badge.plus", text: "Nenhum snippet. Ex.: “meu e-mail” → seu endereço de e-mail.")
                }
                ForEach(store.items) { s in
                    Card {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("“\(s.trigger)”").font(.headline)
                                Text(s.expansion).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                            }
                            Spacer()
                            Button { store.remove(s.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Style

private struct StylePage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Estilo",
                           subtitle: "Escolha o tom do polimento conforme o tipo de app em que você está ditando. Requer o polimento por LLM ligado.")
                    .padding(.top, 32)
                ForEach(AppCategory.allCases) { StyleRow(category: $0) }
                Text("O tom padrão só corrige pontuação e hesitações; os demais também reescrevem o registro do texto.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }
}

private struct StyleRow: View {
    let category: AppCategory
    @LState private var tone: Tone

    init(category: AppCategory) {
        self.category = category
        _tone = LState(wrappedValue: category.tone)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    Text(category.examples).font(.caption).foregroundStyle(.secondary)
                }
                Picker("", selection: $tone) {
                    ForEach(Tone.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: tone) { var c = category; c.tone = $0 }
            }
        }
    }
}

// MARK: - Scratchpad

private struct ScratchpadPage: View {
    @LState private var text = (try? String(contentsOf: Paths.scratchpad, encoding: .utf8)) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Rascunho", subtitle: "Um bloco de notas para ditar. Clique no texto, segure a tecla de ditado e fale.")
                .padding(.top, 32)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
                .onChange(of: text) { try? $0.write(to: Paths.scratchpad, atomically: true, encoding: .utf8) }
        }
        .padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
    }
}

// MARK: - Settings

private struct SettingsPage: View {
    @AppStorage("hotkey") private var hotkey = Hotkey.rightOption.rawValue
    @AppStorage("commandHotkey") private var commandHotkey = Hotkey.rightControl.rawValue
    @AppStorage("language") private var language = "pt"
    @AppStorage("model") private var model = "ggml-large-v3-turbo-q5_0.bin"
    @AppStorage("cleanFillers") private var cleanFillers = true
    @AppStorage("llmEnabled") private var llmEnabled = true
    @AppStorage("llmModel") private var llmModel = "qwen2.5:3b-instruct"
    @AppStorage("handsFree") private var handsFree = true
    @AppStorage("fieldContext") private var fieldContext = true
    @AppStorage("screenOCR") private var screenOCR = false

    @LState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @LState private var loginError: String?
    @ObservedObject private var perms = PermissionsModel.shared

    private var models: [String] {
        let found = (try? FileManager.default.contentsOfDirectory(atPath: Paths.models.path))?.filter { $0.hasSuffix(".bin") }.sorted() ?? []
        return found.contains(model) ? found : [model] + found
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Configurações", subtitle: "Tudo é salvo automaticamente.").padding(.top, 32)

                section("Ditado") {
                    row("Tecla de ditado", "Segure para falar, solte para inserir.") {
                        Picker("", selection: $hotkey) {
                            ForEach(Hotkey.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }.labelsHidden().frame(width: 190)
                    }
                    row("Tecla de comando", "Selecione um texto, segure e diga o que fazer (ex.: “traduza para inglês”). Sem seleção, escreve um texto novo.") {
                        Picker("", selection: $commandHotkey) {
                            Text("Desligado").tag(0)
                            ForEach(Hotkey.allCases.filter { $0.rawValue != hotkey }, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }.labelsHidden().frame(width: 190)
                    }
                    row("Idioma", "Detecção automática erra mais em frases curtas.") {
                        Picker("", selection: $language) {
                            Text("Português").tag("pt"); Text("English").tag("en"); Text("Español").tag("es")
                            Text("Detectar automaticamente").tag("auto")
                        }.labelsHidden().frame(width: 190)
                    }
                    row("Remover “hum”, “ãh”", "Tira hesitações antes de colar.") { Toggle("", isOn: $cleanFillers).labelsHidden() }
                }

                section("Modelos locais") {
                    row("Transcrição (whisper.cpp)", "Arquivos .bin em \(Paths.models.lastPathComponent)/.") {
                        Picker("", selection: $model) { ForEach(models, id: \.self) { Text($0) } }
                            .labelsHidden().frame(width: 260)
                            .onChange(of: model) { _ in NotificationCenter.default.post(name: .restartWhisper, object: nil) }
                    }
                    row("Polimento por LLM", "Corrige o texto com um modelo do Ollama.") { Toggle("", isOn: $llmEnabled).labelsHidden() }
                    row("Modelo do Ollama", "Ex.: qwen2.5:3b-instruct, llama3.2:3b") {
                        TextField("", text: $llmModel).textFieldStyle(.roundedBorder).frame(width: 220)
                            .onSubmit { NotificationCenter.default.post(name: .reloadLLM, object: nil) }
                    }
                }

                section("Geral") {
                    row("Abrir ao iniciar sessão", loginError ?? "O ditado fica sempre disponível.") {
                        Toggle("", isOn: $launchAtLogin).labelsHidden()
                            .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
                    }
                    row("Diagnóstico", "Teclas, permissões e erros do app (nunca o texto ditado).") {
                        Button("Abrir log") { NSWorkspace.shared.open(Log.url) }
                    }
                    row("Pasta de dados", "Histórico, dicionário, snippets e modelos.") {
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.support]) }
                    }
                }

                section("Contexto e modos") {
                    row("Mãos livres", "Um toque rápido na tecla mantém a gravação ligada; toque de novo para finalizar. Esc cancela.") {
                        Toggle("", isOn: $handsFree).labelsHidden()
                    }
                    row("Contexto do campo de texto", "Lê o texto ao redor do cursor e o título da janela (Acessibilidade) para acertar nomes, maiúsculas e espaços.") {
                        Toggle("", isOn: $fieldContext).labelsHidden()
                    }
                    row("Ler a tela (OCR)", "Reconhece o texto da janela em foco enquanto você fala. Mais lento; exige Gravação de Tela.") {
                        Toggle("", isOn: $screenOCR).labelsHidden()
                            .onChange(of: screenOCR) { on in if on { ScreenContext.warmUpOCR() } }
                    }
                }

                section("Permissões") {
                    ForEach(Permission.allCases.filter { $0 != .screenRecording || screenOCR }) { p in
                        HStack {
                            Image(systemName: perms.granted[p] == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(perms.granted[p] == true ? Color.green : Color.orange)
                            Text(p.title)
                            Spacer()
                            if perms.granted[p] != true { Button("Ativar") { p.request() } }
                        }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Não foi possível alterar: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Card { VStack(spacing: 12) { content() } }
        }
    }

    private func row<C: View>(_ title: String, _ detail: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    private func permission(_ name: String, _ granted: Bool, _ url: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(name)
            Spacer()
            if !granted {
                Button("Abrir ajustes") { NSWorkspace.shared.open(URL(string: url)!) }
            }
        }
    }
}
