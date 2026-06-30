# RueDex V4 — correctif script PowerShell

Ce correctif corrige uniquement `tools/configure_android.ps1`.

Le script précédent utilisait `\"debug\"`, qui casse PowerShell. Cette version utilise l'échappement PowerShell correct.

## Installation

1. Copier le dossier `tools` dans le projet RueDex.
2. Accepter le remplacement.
3. Commit : `Correctif script PowerShell V4`
4. Push origin.
