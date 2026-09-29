# Instalador do GRADE

O **GRADE** é o sistema de geração e otimização de grade horária escolar da GLeme Labs. Este repositório contém apenas o instalador para rodar o GRADE no servidor da própria escola (Self-Hosted).

O código do produto é fechado; o que roda no servidor vem das imagens publicadas em `ghcr.io/glemelabs`.

## Requisitos

| Item      | Mínimo                                            | Recomendado                    |
| --------- | ------------------------------------------------- | ------------------------------ |
| CPU       | 2 vCPU                                            | 4 vCPU (gerações mais rápidas) |
| Memória   | 4 GB                                              | 8 GB                           |
| Disco     | 20 GB livres                                      | 50 GB (backups diários)        |
| Sistema   | Linux x86-64 ou ARM64, ou Windows com Docker      | Ubuntu 24.04 LTS               |
| Rede      | Portas 80 e 443 livres                            |                                |

O instalador instala o Docker se ele não existir e usa outras portas (8080 e 8443) caso as padrão estejam ocupadas.

## Instalação no Linux

```bash
curl -fsSL https://raw.githubusercontent.com/glemelabs/grade-install/main/install.sh -o install.sh
sudo bash install.sh
```

Sem perguntas (automação):

```bash
sudo GRADE_NONINTERACTIVE=1 GRADE_DOMAIN=grade.suaescola.local bash install.sh
```

## Instalação no Windows

Com o [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado, num PowerShell **como administrador**:

```powershell
curl.exe -fsSL https://raw.githubusercontent.com/glemelabs/grade-install/main/install.ps1 -o install.ps1
powershell -ExecutionPolicy Bypass -File install.ps1
```

## Depois de instalar

O instalador grava um `ACESSO.txt` na pasta da instalação (`/opt/grade` no Linux, `C:\GRADE` no Windows) com o endereço, onde ficam as senhas e os comandos do dia a dia. Em seguida:

1. abra o endereço mostrado e crie o administrador e a escola;
2. em **Configurações › Licença**, carregue o arquivo `.lic` recebido por e-mail.

Sem licença, o sistema funciona completo por 30 dias de avaliação.

## Dia a dia

| O quê       | Linux                              | Windows                                                    |
| ----------- | ---------------------------------- | ---------------------------------------------------------- |
| Atualizar   | `sudo bash /opt/grade/atualizar.sh` | `powershell -ExecutionPolicy Bypass -File C:\GRADE\atualizar.ps1` |
| Ver estado  | `cd /opt/grade && docker compose ps` | `cd C:\GRADE; docker compose ps`                           |
| Ver erros   | `cd /opt/grade && docker compose logs web` | `cd C:\GRADE; docker compose logs web`               |
| Desinstalar | `sudo bash /opt/grade/desinstalar.sh` | `powershell -ExecutionPolicy Bypass -File C:\GRADE\desinstalar.ps1` |

O backup roda todo dia às 2h e fica disponível em **Configurações › Backup**.

## Servidor sem internet

Peça o pacote offline à GLeme Labs (imagens em arquivo). No servidor:

```bash
gunzip -c grade-imagens.tar.gz | sudo docker load
sudo GRADE_NONINTERACTIVE=1 GRADE_SKIP_PULL=1 bash install.sh
```

A licença é ativada pelo modo offline, descrito no manual que acompanha a compra.

## Variáveis aceitas (Linux)

| Variável                | Para quê                                              |
| ----------------------- | ----------------------------------------------------- |
| `GRADE_DIR`             | pasta da instalação (padrão `/opt/grade`)             |
| `GRADE_DOMAIN`          | endereço de acesso                                     |
| `GRADE_EMAIL`           | e-mail do certificado Let's Encrypt                    |
| `GRADE_VERSION`         | linha de versão das imagens (padrão `1`)               |
| `GRADE_NONINTERACTIVE`  | `1` aceita os padrões sem perguntar                    |
| `GRADE_INSTALL_DOCKER`  | `0` não instala o Docker automaticamente               |
| `GRADE_SKIP_PULL`       | `1` usa imagens já carregadas (pacote offline)         |
| `GRADE_HTTP_PORT` / `GRADE_HTTPS_PORT` | portas fixas                            |
| `GRADE_MIN_DISK_GB`     | espaço livre mínimo exigido (padrão 10)                |

No Windows, os mesmos ajustes são parâmetros: `-Dir`, `-Domain`, `-Email`, `-Version`, `-SkipPull`, `-NoDockerInstall`, `-HttpPort`, `-HttpsPort`, `-MinDiskGb`.

## Suporte

Dúvidas sobre licença e instalação: **suporte@glemelabs.com**.

Este instalador é publicado pela GLeme Labs. O GRADE é software proprietário, licenciado conforme o contrato de licença de uso aceito na compra.
