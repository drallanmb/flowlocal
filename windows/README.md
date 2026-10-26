# FlowLocal para Windows

Ditado por voz **local** para Windows, no mesmo estilo da versão para macOS: segure uma tecla, fale, solte — o texto é transcrito pelo whisper.cpp, polido por um LLM local (Ollama) e colado no app em foco. Nada sai do seu PC.

> **Estado:** a lógica compartilhada (limpeza de texto, ajuste ao cursor, prompts, dicionário, snippets, histórico) tem testes automáticos e passa. O app WPF compila, mas **ainda não foi executado num Windows real**: teclado global, microfone, colar e o Hub precisam do seu teste. Se algo falhar, veja `%APPDATA%\FlowLocal\flowlocal.log`.

## Instalar

1. **Baixe o app.** No GitHub, abra *Actions → Windows build* e baixe o artefato `FlowLocal-win-x64` (um `FlowLocal.exe` autossuficiente, sem precisar instalar o .NET), ou compile (veja abaixo).
2. **Instale os motores locais** (PowerShell, na pasta do projeto):
   ```powershell
   .\windows\scripts\setup.ps1
   ```
   Ele baixa o whisper.cpp (versão **CUDA** se houver GPU NVIDIA; senão CPU), o modelo de voz `large-v3-turbo-q5_0` (~570 MB) e instala o Ollama com `qwen2.5:3b-instruct` (~1,9 GB). Use `-Gpu cpu` para forçar CPU ou `-SkipOllama` para só transcrever.
3. **Abra o FlowLocal.** O Hub mostra uma lista “Configuração inicial” e marca cada item com ✓ quando estiver pronto.

## Usar

- Segure a **tecla de ditado** (padrão: **Ctrl direito**), fale e solte: o texto é colado onde estiver o cursor.
- **Mãos livres:** um toque rápido (< 0,3 s) liga a gravação; toque de novo para finalizar. **Esc** cancela.
- **Modo comando:** escolha uma tecla em *Configurações → Tecla de comando*, selecione um texto, segure a tecla e diga “traduza para inglês”, “deixe mais formal”… Sem seleção, a instrução vira um pedido de texto novo.
- Se você segurar a tecla e apertar **outra** (por exemplo Ctrl+C), o app entende que era um atalho e descarta a gravação.

## Diferenças em relação ao macOS

| macOS | Windows |
|---|---|
| Tecla Fn/Globe | O Windows não expõe o Fn. Teclas disponíveis: Ctrl direito, Alt direito, Shift direito, Scroll Lock, Pause, F9–F12. |
| Permissões de Microfone, Acessibilidade e Monitoramento | Só o microfone (*Configurações do Windows → Privacidade → Microfone → apps da área de trabalho*). Teclado global, UI Automation e colar não pedem permissão. |
| Ícone na barra de menus | Ícone na bandeja do sistema (L com ondas; 3 ondas enquanto grava). |
| Contexto da tela por Acessibilidade + OCR (Vision) | UI Automation para o texto ao redor do cursor; OCR opcional com o OCR do Windows (offline, exige um pacote de idioma de OCR). |
| Metal | CUDA (NVIDIA) ou CPU. Sem NVIDIA, o `large-v3-turbo` pode levar vários segundos; prefira um modelo menor (`ggml-small-q5_1.bin`) em *Configurações → Modelos locais*. |

**Limites conhecidos**
- Não dá para colar em janelas executadas **como administrador** (o Windows bloqueia entrada simulada vinda de um app comum).
- Em teclados **ABNT2**, o Alt direito é o AltGr: use Ctrl direito, Scroll Lock ou uma tecla F.
- Alguns apps (navegadores sem acessibilidade ligada, jogos, terminais antigos) não expõem o texto do campo; nesses o ajuste ao cursor simplesmente não acontece.

## Compilar

```powershell
dotnet test windows\tests\FlowLocal.Core.Tests
dotnet publish windows\src\FlowLocal.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```
Requer o .NET 8 SDK. O projeto está dividido em `FlowLocal.Core` (lógica pura, roda em qualquer sistema e é testada) e `FlowLocal.App` (WPF, teclado global, áudio, colar, UI Automation, OCR, bandeja e Hub).

## Dados

Em `%APPDATA%\FlowLocal`: `settings.json`, `dictionary.json`, `snippets.json`, `history.jsonl` (mesmos formatos do macOS), `scratchpad.txt`, `flowlocal.log` e `models\`. O whisper.cpp fica em `%LOCALAPPDATA%\FlowLocal\whisper`.
