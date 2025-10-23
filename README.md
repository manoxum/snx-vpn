# SNX VPN Container Manager 🚀

[![Docker](https://img.shields.io/badge/Docker-Container-blue?logo=docker)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Um utilitário simples para gerenciar o container `snx-vpn` via Docker, com suporte a binds de portas, SSH e logs.

---

## 🔧 Instalação

1. Clone ou baixe este repositório:

```bash
git clone <repo-url>
cd <repo-folder>
```

2. Execute o script de instalação:

```bash
./install.sh
```

O script fará:

- 🛠 Construir a imagem Docker `snx-vpn`.
- 🔓 Tornar o script `snx.sh` executável.
- 🔗 Criar um link simbólico em `~/.local/bin/snx` para uso global.

> ⚠️ Certifique-se de que `~/.local/bin` esteja no seu PATH:
>
> ```bash
> echo $PATH
> ```

---

## 🚀 Uso

Após a instalação, utilize o comando `snx` para gerenciar o container.

### 📋 Comandos disponíveis

| Comando | Descrição |
|---------|-----------|
| `snx` | Abre um shell Bash dentro do container `snx-vpn`. |
| `snx connect` / `snx start` / `snx init` | Inicializa e cria o container caso ainda não exista. |
| `snx reconnect` / `snx restart` | Remove e recria o container, preservando binds configurados. |
| `snx stop` / `snx disconnect` | Para e remove o container `snx-vpn`. |
| `snx ssh <args...>` | Executa um comando SSH dentro do container. Ex: `snx ssh user@10.0.0.5`. |
| `snx bind A:B` | Adiciona um novo bind de porta (ex: `snx bind 8080:80`) e recria o container. |
| `snx ports` | Lista todos os binds de portas atuais do container. |
| `snx logs` | Exibe os logs do container `snx-vpn`. |
| `snx --help` | Mostra esta mensagem de ajuda detalhada. |

---

## ⚙️ Configuração

O script lê a variável `SSH_BIND` do arquivo `.env.local`:

```env
SSH_BIND=2222:22
```

- Formato: `HOST_PORT:CONTAINER_PORT`
- Usada para mapear a porta SSH do host para o container.

---

## 💡 Exemplos de uso

- Abrir bash no container:

```bash
snx
```

- Reconectar/recriar o container:

```bash
snx reconnect
```

- Adicionar um novo bind de porta:

```bash
snx bind 8080:80
```

- Listar todas as portas expostas:

```bash
snx ports
```

- Conectar via SSH dentro do container:

```bash
snx ssh user@10.0.0.5
```

- Visualizar logs:

```bash
snx logs
```

- Parar o container:

```bash
snx stop
```

---

## 🛠 Recursos

- Container Docker leve e rápido
- Bind dinâmico de portas
- SSH interno fácil
- Logs acessíveis
- Recriação segura do container

---

## 💖 Feito com ❤️

Para gerenciar facilmente seu container `snx-vpn`, sem complicações.