# SNX VPN Container Manager 🚀

Gerencie facilmente seu container `snx-vpn` via Docker com suporte a binds de portas dinâmicos, SSH interno e logs detalhados.

---

## 🔧 Instalação

1. Clone ou baixe este repositório:

```bash
git clone https://github.com/manoxum/snx-vpn.git
cd snx-vpn
```

2. Execute o script de instalação:

```bash
./install.sh
```

O script irá:

* 🛠 Reconstruir sem cache a imagem Docker definida em `SNX_IMAGE` (padrão: `snx`).
* 🔓 Tornar `snx.sh` executável.
* 🔗 Criar link simbólico em `~/.local/bin/snx` para uso global.
* ⌨️ Instalar autocomplete para Bash e Zsh.
* ♻️ Recriar o container se ele já existir, mantendo portas e modo de rede.

O `install.sh` usa o mesmo fluxo de `snx install`. O build precisa concluir com
sucesso antes de atualizar a instalação ou recriar um container existente.

> ⚠️ Certifique-se de que `~/.local/bin` esteja no seu PATH:
>
> Se o diretório não estiver no PATH, adicione-o adicionando a seguinte linha ao seu arquivo `~/.bashrc` ou `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

> Depois, recarregue o shell ou execute `source ~/.bashrc` (ou `source ~/.zshrc`).

```bash
echo $PATH
```

---

## 🚀 Uso

Use o comando `snx` para gerenciar o container.

Antes de criar ou recriar o container, o `snx` verifica se a imagem definida em
`SNX_IMAGE` (padrão: `snx`) existe localmente. Se não existir, executa
`docker build -t "${SNX_IMAGE:-snx}" .` no diretório do projeto automaticamente.
Se o build falhar, o comando para sem remover o container existente.

### 📋 Comandos disponíveis

| Comando                    | Descrição                                                        |
| -------------------------- | ---------------------------------------------------------------- |
| `snx`                      | Abre um shell Bash dentro do container `snx-vpn`.                |
| `snx install`              | Instala/reinstala o comando, reconstrói a imagem sem cache e recria um container existente. |
| `snx build\|rebuild\|reinstall` | Aliases de `snx install`.                                    |
| `snx uninstall`            | Remove a instalação, o container e as imagens do SNX, mantendo repositório e envs. |
| `snx connect\|start\|init` | Inicializa e cria o container se não existir.                    |
| `snx reconnect\|restart`   | Remove e recria o container com binds existentes.                |
| `snx stop\|disconnect`     | Para e remove o container.                                       |
| `snx ssh <args...>`        | Executa um comando SSH no container. Ex: `snx ssh user@10.0.0.5` |
| `snx bind A:B`             | Adiciona um bind de porta e recria o container.                  |
| `snx expose on\|off`       | Ativa/desativa rede host (ignora binds se `on`).                 |
| `snx ports`                | Lista todos os binds de portas atuais.                           |
| `snx logs`                 | Exibe os logs do container.                                      |
| `snx status`               | Mostra informações detalhadas (imagem, portas, mounts, status).  |
| `snx --help\|-h`           | Mostra ajuda detalhada.                                          |

---

## ⌨️ Autocomplete

O autocomplete é instalado por `./install.sh` ou `snx install`. Abra um novo
terminal ou recarregue a configuração do seu shell:

```bash
source ~/.bashrc  # Bash
# ou: source ~/.zshrc  # Zsh
```

Use `snx <Tab>` para listar os comandos, `snx re<Tab>` para completar os aliases
de reconstrução/reconexão e `snx expose <Tab>` para escolher `on` ou `off`.

Os arquivos de autocomplete ficam em `~/.local/share/snx/completions`. A
instalação adiciona um bloco identificado às configurações do shell e atualiza
esse mesmo bloco nas reinstalações.

## 🗑️ Desinstalação

```bash
snx uninstall
```

Esse comando remove:

* O container definido em `SNX_NAME`, incluindo sua camada temporária e volumes anônimos.
* A imagem definida em `SNX_IMAGE` e imagens antigas sem tag identificadas como builds dessa imagem do SNX.
* O link `~/.local/bin/snx` quando ele aponta para este repositório.
* Os arquivos de autocomplete instalados e os blocos de integração em `.bashrc` e `.zshrc`.

A pasta do repositório e todos os seus arquivos, incluindo `.env`, `.env.local`
e outros envs, são preservados. O cache compartilhado do Docker e recursos de
outros projetos são mantidos. Após desinstalar, execute `./install.sh` na pasta
do repositório para instalar novamente.

---

## ⚙️ Configuração

O container carrega variáveis de `.env.local`:

```env
SNX_SSH_BIND=2222
```

* `HOST_PORT:CONTAINER_PORT` para SSH.
* Configure usuário/senha SSH, nome da imagem e do container.

Exemplo de `.env.local`:

```env
SNX_VPN_USERNAME=testuser
SNX_VPN_PASSWORD=secret123
SNX_VPN_GETWAI=vpn.example.com
SNX_SSH_USER=jumphost
SNX_SSH_PASSWORD=password123
SNX_SSH_BIND=2222
SNX_IMAGE=snx
SNX_NAME=snx
```

---

## 💡 Exemplos de uso

```bash
snx                  # Abrir shell no container
snx install           # Instalar/reinstalar e reconstruir sem cache
snx rebuild           # Alias de install
snx uninstall         # Remover instalação, mantendo repositório e envs
snx connect           # Criar container se não existir
snx reconnect         # Recriar container
snx stop              # Parar container
snx ssh user@10.0.0.5 # Executar SSH
snx bind 8080:80      # Adicionar bind de porta
snx expose on         # Ativar rede host
snx expose off        # Desativar rede host
snx ports             # Listar portas
snx logs              # Ver logs
snx status            # Status completo do container
```

---

## 🛠 Recursos

* Container Docker leve e rápido
* Bind de portas dinâmico
* SSH interno configurável
* Logs detalhados e acessíveis
* Recriação segura do container
* Rede host opcional
* Configuração simples via `.env.local`

---

## ⚠️ Notas

* Variáveis do `.env.local` são carregadas automaticamente.
* `SNX_SSH_BIND` define a porta SSH externa (default: 2222).
* `HOST_EXPOSED` controla uso da rede host (ignora binds se `on`).
* Sempre use `snx status` para verificar o container.

---

## 📝 Estrutura do Projeto

```
├── app/                     # Scripts e binários do container
│   ├── bin/                 # Entrypoints e scripts auxiliares
│   └── lib/                 # Scripts de instalação VPN
├── Dockerfile               # Imagem base e setup
├── completions/             # Autocomplete para Bash e Zsh
├── install.sh               # Script de instalação e build
├── snx.sh                   # Script principal de gerenciamento
├── .env.local               # Variáveis de configuração (exemplo)
└── README.md
```

---

Gerencie seu VPN container de forma segura e prática, com SSH interno, binds dinâmicos e suporte completo a logs e status.

Para mais informações, acesse o repositório oficial: [https://github.com/manoxum/snx-vpn](https://github.com/manoxum/snx-vpn)
