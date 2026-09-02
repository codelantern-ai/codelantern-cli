# codelantern

Install the **codelantern** CLI. Prebuilt binaries for macOS, Linux, and Windows.

## macOS / Linux

```sh
curl -fsSL https://raw.githubusercontent.com/codelantern-ai/codelantern-cli/main/install.sh | bash
```

## Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/codelantern-ai/codelantern-cli/main/install.ps1 | iex
```

Each installer downloads the release archive for your OS/architecture, verifies it against
`checksums.txt`, and installs the `codelantern` binary — to `~/.local/bin` on macOS/Linux, or
`%LOCALAPPDATA%\Programs\codelantern` on Windows. It prints `codelantern --version` on success; if the
install directory isn't on your `PATH`, it tells you how to add it.

> First run may show an OS "unidentified developer" (macOS) or SmartScreen (Windows) warning — the
> binaries aren't code-signed yet. Allow it once and it won't recur for that download.
