# FlowLocal

Ditado por voz local para macOS (estilo Wispr Flow): segure uma tecla, fale, solte — o texto é transcrito pelo whisper.cpp (Metal) e colado no app em foco.

## Requisitos
- `brew install whisper.cpp` (fornece `whisper-server`)
- `brew install ollama` e `ollama pull qwen2.5:3b-instruct` (polimento por LLM; o app inicia `ollama serve` sozinho)
- Modelo em `~/Library/Application Support/FlowLocal/models/ggml-large-v3-turbo-q5_0.bin`
  (https://huggingface.co/ggerganov/whisper.cpp). Outro modelo: ajuste `Settings.modelFile`.

## Ícone
`scripts/make_icon.swift` desenha o ícone (um “L” emitindo ondas sonoras; arte original) e gera `Resources/AppIcon.icns`. O ícone da barra de menus é desenhado em código (`MenuBarIcon.swift`) como imagem *template*: 2 ondas em repouso, 3 ao gravar.

## Uso
```bash
./build.sh && open FlowLocal.app
```
1. Conceda **Microfone**, **Acessibilidade** e **Monitoramento de Entrada** (Ajustes do Sistema → Privacidade e Segurança) e reabra o app.
2. Segure a tecla de ditado (padrão: **Option direito**; troque no menu) e fale. Solte para inserir o texto.

## Como funciona
`HotkeyMonitor` (flagsChanged global) → `AudioRecorder` (AVAudioEngine, 16 kHz mono) → `WhisperServer` (processo `whisper-server` local, modelo fica carregado) → `TextCleaner` (hesitações, pontuação falada, dicionário) → `LLMPolisher` (Ollama; se falhar ou demorar >12 s, usa o texto sem polir) → `TextInserter` (clipboard + Cmd+V, depois restaura o clipboard).

- Dicionário pessoal: menu → *Editar dicionário pessoal…* (`{"como falou": "como escrever"}`); os termos também viram prompt para o whisper.
- Comandos falados: "vírgula", "ponto final", "ponto de interrogação", "nova linha", "novo parágrafo", etc.
- Histórico local: `~/Library/Application Support/FlowLocal/history.jsonl`.
- Tudo roda offline; nenhum áudio sai da máquina.

## Mãos livres
Um **toque rápido** (menos de 0,3 s) na tecla de ditado trava a gravação; fale à vontade e toque de novo para finalizar. **Esc** cancela. Segurar a tecla continua funcionando como push-to-talk. Desligue em Configurações → Contexto e modos.

## Contexto da tela
Ao começar a falar, o app lê, **só no seu Mac**: o app e o título da janela, o texto antes e depois do cursor no campo (Acessibilidade; campos de senha são ignorados) e, se ligado, o texto da janela em foco por OCR (Vision + Gravação de Tela). Esse contexto (1) leva nomes vistos na tela ao prompt do whisper, (2) vai ao LLM como dados não confiáveis para acertar grafia e continuar o texto, e (3) ajusta o resultado ao campo: espaço depois da palavra anterior e inicial minúscula no meio de uma frase.

## Permissões
O Hub guia **uma permissão por vez** (Microfone, Acessibilidade, Monitoramento de Entrada e, com OCR, Gravação de Tela): abre o painel certo e só marca ✓ quando o macOS confirma. O log registra cada mudança em `flowlocal.log`.

## Modo comando
Segure a **tecla de comando** (padrão: Control direito; configurável ou desligável no Hub), diga o que fazer com o texto selecionado — “traduza para inglês”, “deixe mais formal”, “transforme em lista” — e solte: o LLM local reescreve e substitui a seleção (Cmd+Z desfaz). Sem seleção, a instrução vira um pedido de texto novo. A seleção é lida pela Acessibilidade, com Cmd+C como alternativa. Modelos de 3B acertam instruções simples; para edições mais sutis use um modelo maior no Ollama.

## Hub
Janela principal (abre ao iniciar e ao clicar no Dock; fechar volta ao modo só barra de menus): **Início** (histórico com busca, copiar/apagar, estatísticas), **Dicionário**, **Snippets** (diga a frase, cole o texto; sem LLM), **Estilo** (tom por tipo de app: e-mail, trabalho, pessoal, outros), **Rascunho** e **Configurações** (tecla, idioma, modelos, abrir no login, status das permissões).
`FlowLocal --snapshot <pasta>` renderiza todas as páginas em PNG; `FLOWLOCAL_DATA_DIR` aponta para dados de teste.

## Ainda não existe (vs. Wispr)
Reuniões e notas (captura do áudio do sistema).

## Licença e aviso
MIT (veja `LICENSE`). FlowLocal é um projeto independente, inspirado no fluxo de ditado do Wispr Flow, e **não tem afiliação** com a Wispr. Todo o código, o ícone e os textos foram escritos do zero; nenhum código, asset ou serviço do Wispr é usado ou necessário.
