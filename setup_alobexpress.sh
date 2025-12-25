#!/bin/bash
set -e

# ==========================================
#  🚀 INFRASTRUCTURE SETUP
#  Version: 3.1.0 - MULTI-CLOUD SWARM (AWS & GCP)
#  Author: AlobExpress Team
#  Updated: 2025-12-25
# ==========================================

# ===== CORES ANSI =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Ícones
CHECK="${GREEN}✓${RESET}"
CROSS="${RED}✗${RESET}"
ARROW="${CYAN}→${RESET}"
WARN="${YELLOW}⚠${RESET}"
INFO="${BLUE}ℹ${RESET}"
ROCKET="${MAGENTA}🚀${RESET}"

# ===== VARIÁVEIS GLOBAIS =====
IS_AWS=false
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
S3_REGION=""
S3_BUCKET_NAME=""

# ===== FUNÇÕES DE UI =====
print_banner() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}${MAGENTA}🚀 INFRASTRUCTURE SETUP v3.1.0${RESET}                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}║${RESET}  ${DIM}Suporte Multi-Cloud: AWS & GCP (Unified Swarm)${RESET}          ${CYAN}║${RESET}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_step() {
    echo -e "\n${BOLD}${BLUE}▶${RESET} ${BOLD}$1${RESET}"
}

print_success() {
    echo -e "  ${CHECK} ${GREEN}$1${RESET}"
}

print_error() {
    echo -e "  ${CROSS} ${RED}$1${RESET}"
}

print_warning() {
    echo -e "  ${WARN} ${YELLOW}$1${RESET}"
}

print_info() {
    echo -e "  ${INFO} ${CYAN}$1${RESET}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [${CYAN}%c${RESET}] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ===== FUNÇÕES AUXILIARES =====
install_docker() {
    if ! command -v docker &> /dev/null; then
        print_info "Instalando Docker..."
        {
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            systemctl enable docker
            systemctl start docker
        } > /tmp/docker_install.log 2>&1 &
        spinner $!
        print_success "Docker Instalado"
    else
        print_success "Docker já está instalado"
    fi
}

# ===== ARQUITETURA SWARM (COMUM) =====
setup_swarm_architecture() {
    # Inicializar Swarm
    if ! docker info | grep -q "Swarm: active"; then
        print_info "Inicializando Docker Swarm..."
        docker swarm init > /dev/null 2>&1 || print_warning "Swarm já iniciado ou erro ao iniciar"
    fi
    
    # Criar rede pública
    if ! docker network ls | grep -q "network_swarm_public"; then
        docker network create --driver overlay --attachable network_swarm_public
        print_success "Rede 'network_swarm_public' criada"
    fi

    # Criar volumes externos necessários
    print_info "Criando volumes persistentes..."
    docker volume create volume_swarm_shared >/dev/null
    docker volume create volume_swarm_certificates >/dev/null
    docker volume create portainer_data >/dev/null
    docker volume create postgres_data >/dev/null
    docker volume create redis_data >/dev/null
    print_success "Volumes criados"

    # Passo 1.1 Configuração Multi-VM (Labeling)
    print_step "CONFIGURAÇÃO DE NÓS (LABELING)"
    echo -e "${YELLOW}Aplicando label 'app=n8n' neste nó (Manager)...${RESET}"
    docker node update --label-add app=n8n $(hostname) >/dev/null 2>&1
    print_success "Label 'app=n8n' aplicada"

    # Aviso DNS Cloudflare
    print_step "VERIFICAÇÃO DE DNS (CLOUDFLARE)"
    echo -e "${YELLOW}Antes de continuar, certifique-se de que os apontamentos DNS foram feitos:${RESET}"
    echo -e "1. Crie um registro A para o IP desta VM"
    echo -e "2. Crie CNAMEs para os serviços (painel, editor, webhook) apontando para o registro A"
    echo -e "3. Use 'DNS Only' (Nuvem Cinza) no Cloudflare inicialmente para gerar SSL"
    read -p "$(echo -e ${BOLD}${GREEN}"Os DNS estão configurados corretamente? (s/n): "${RESET})" DNS_CONFIRM
    if [[ ! "$DNS_CONFIRM" =~ ^(s|S|sim|SIM)$ ]]; then 
        print_error "Configure o DNS e execute novamente."
        exit 0
    fi

    # Coleta de Dados
    print_step "PASSO 2: DEPLOY DOS SERVIÇOS - CONFIGURAÇÃO"
    
    read -p "$(echo -e ${CYAN}"📧 E-mail para SSL (Traefik): "${RESET})" TRAEFIK_EMAIL
    
    echo -e "\n${BOLD}${MAGENTA}=== PORTAINER ===${RESET}"
    read -p "$(echo -e ${CYAN}"🌍 Domínio do Portainer (ex: painel.seu-dominio.com): "${RESET})" PORTAINER_DOMAIN
    
    echo -e "\n${BOLD}${MAGENTA}=== BANCO DE DADOS ===${RESET}"
    read -sp "$(echo -e ${CYAN}"🔒 Senha para o PostgreSQL: "${RESET})" POSTGRES_PASSWORD
    echo ""
    read -sp "$(echo -e ${CYAN}"🔒 Senha para o Redis: "${RESET})" REDIS_PASSWORD
    echo ""
    
    echo -e "\n${BOLD}${MAGENTA}=== N8N ===${RESET}"
    read -p "$(echo -e ${CYAN}"🌍 Domínio do Editor N8N (ex: editor.seu-dominio.com): "${RESET})" N8N_EDITOR_DOMAIN
    read -p "$(echo -e ${CYAN}"🌍 Domínio do Webhook N8N (ex: webhook.seu-dominio.com): "${RESET})" N8N_WEBHOOK_DOMAIN
    read -p "$(echo -e ${CYAN}"🔑 N8N Encryption Key (ex: gere uma aleatória): "${RESET})" N8N_ENCRYPTION_KEY
    
    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
        print_info "Chave gerada automaticamente: $N8N_ENCRYPTION_KEY"
    fi

    # Geração dos Arquivos YAML
    print_step "GERANDO ARQUIVOS DE CONFIGURAÇÃO (YAML)"
    
    # 04.traefik.yaml
    cat <<EOF > 04.traefik.yaml
version: "3.7"

services:
  traefik:
    image: traefik:v3.6.4
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command:
      - "--api.dashboard=true"
      - "--providers.swarm=true"
      - "--providers.swarm.endpoint=unix:///var/run/docker.sock"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=network_swarm_public"
      - "--core.defaultRuleSyntax=v2"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.web.http.redirections.entryPoint.permanent=true"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=${TRAEFIK_EMAIL}"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--log.level=INFO"
      - "--accesslog=true"
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
        - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-https@swarm"
        - "traefik.http.routers.http-catchall.priority=1"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "vol_certificates:/etc/traefik/letsencrypt"
    networks:
      - network_swarm_public
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host

volumes:
  vol_shared:
    external: true
    name: volume_swarm_shared
  vol_certificates:
    external: true
    name: volume_swarm_certificates

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 05.portainer.yaml
    cat <<EOF > 05.portainer.yaml
version: "3.7"

services:
  agent:
    image: portainer/agent:2.33.5
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_swarm_public
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.33.5
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=network_swarm_public"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  network_swarm_public:
    external: true
    attachable: true
    name: network_swarm_public

volumes:
  portainer_data:
    external: true
    name: portainer_data
EOF

    # 06.postgres.yaml
    cat <<EOF > 06.postgres.yaml
version: "3.7"
services:
  postgres:
    image: postgres:16-alpine
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - PGDATA=/var/lib/postgresql/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

volumes:
  postgres_data:
    external: true
    name: postgres_data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 07.redis.yaml
    cat <<EOF > 07.redis.yaml
version: "3.7"
services:
  redis:
    image: redis:7-alpine
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: redis-server --appendonly yes --port 6379 --requirepass ${REDIS_PASSWORD}
    networks:
      - network_swarm_public
    volumes:
      - redis_data:/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

volumes:
  redis_data:
    external: true
    name: redis_data
networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # DEFINIÇÃO DE VARIÁVEIS N8N
    AWS_ENV=""
    if [ "$IS_AWS" = true ]; then
        AWS_ENV=$(cat <<AWS_BLOCK
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - S3_REGION=${S3_REGION}
      - S3_BUCKET_NAME=${S3_BUCKET_NAME}
AWS_BLOCK
)
    fi

    N8N_ENV_BLOCK=$(cat <<ENV_BLOCK
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
${AWS_ENV}
      - NODE_ENV=production
      - N8N_PAYLOAD_SIZE_MAX=16
      - N8N_LOG_LEVEL=info
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_PORT=5678
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_EDITOR_DOMAIN}/
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336
ENV_BLOCK
)

    # 08.n8n-editor.yaml
    cat <<EOF > 08.n8n-editor.yaml
version: "3.7"
services:
  n8n_editor:
    image: n8nio/n8n:2.0.2
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: start
    networks:
      - network_swarm_public
    environment:
$N8N_ENV_BLOCK
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=network_swarm_public"
        - "traefik.http.routers.n8n_editor.rule=Host(\`${N8N_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.n8n_editor.entrypoints=websecure"
        - "traefik.http.routers.n8n_editor.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_editor.service=n8n_editor"
        - "traefik.http.services.n8n_editor.loadbalancer.server.port=5678"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 09.n8n-workers.yaml
    cat <<EOF > 09.n8n-workers.yaml
version: "3.7"
services:
  n8n_worker:
    image: n8nio/n8n:2.0.2
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: worker --concurrency=10
    networks:
      - network_swarm_public
    environment:
$N8N_ENV_BLOCK
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 10.n8n-webhooks.yaml
    cat <<EOF > 10.n8n-webhooks.yaml
version: "3.7"
services:
  n8n_webhook:
    image: n8nio/n8n:2.0.2
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: webhook
    networks:
      - network_swarm_public
    environment:
$N8N_ENV_BLOCK
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=network_swarm_public"
        - "traefik.http.routers.n8n_webhook.rule=Host(\`${N8N_WEBHOOK_DOMAIN}\`)"
        - "traefik.http.routers.n8n_webhook.entrypoints=websecure"
        - "traefik.http.routers.n8n_webhook.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_webhook.service=n8n_webhook"
        - "traefik.http.services.n8n_webhook.loadbalancer.server.port=5678"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    print_success "Arquivos YAML gerados com sucesso!"

    # Passo 2 (Execução): Iniciar Serviços
    print_step "INICIANDO SERVIÇOS DE INFRAESTRUTURA"
    
    # 1. Traefik e Portainer
    docker stack deploy -c 04.traefik.yaml traefik
    docker stack deploy -c 05.portainer.yaml portainer
    
    print_info "Aguardando serviços de infraestrutura subirem (15s)..."
    sleep 15
    
    # 2. Bancos de Dados
    docker stack deploy -c 06.postgres.yaml postgres
    docker stack deploy -c 07.redis.yaml redishe
    
    print_info "Aguardando bancos de dados inicializarem (30s)..."
    sleep 30

    # 3. Criação do Banco N8N
    print_step "CONFIGURANDO BANCO DE DADOS N8N"
    print_info "Tentando conectar ao Postgres para criar o banco 'n8n'..."
    
    # Loop para encontrar o container ID do postgres (pode demorar um pouco no swarm)
    POSTGRES_CONTAINER=""
    for i in {1..10}; do
        POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
        if [ -n "$POSTGRES_CONTAINER" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "$POSTGRES_CONTAINER" ]; then
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE n8n;" >/dev/null 2>&1; then
            print_success "Banco de dados 'n8n' criado com sucesso!"
        else
            print_warning "Banco de dados 'n8n' já existe ou erro na criação (verifique logs)."
        fi
    else
        print_error "Não foi possível encontrar o container do Postgres. Crie o banco 'n8n' manualmente depois."
    fi

    # 4. Deploy Aplicações
    print_step "DEPLOY DAS APLICAÇÕES DE NEGÓCIO (N8N)"
    docker stack deploy -c 08.n8n-editor.yaml n8n_editor
    docker stack deploy -c 09.n8n-workers.yaml n8n_worker
    docker stack deploy -c 10.n8n-webhooks.yaml n8n_webhook
    
    # Resumo Final
    print_step "SETUP CONCLUÍDO!"
    if [ "$IS_AWS" = true ]; then
        echo -e "${GREEN}✅ Infraestrutura AWS (Swarm) implantada!${RESET}"
    else
        echo -e "${GREEN}✅ Infraestrutura Google Cloud (Swarm) implantada!${RESET}"
    fi
    echo ""
    echo -e "${BOLD}${CYAN}Acesse seus serviços:${RESET}"
    echo -e "   ${ARROW} Portainer: https://${PORTAINER_DOMAIN}"
    echo -e "   ${ARROW} N8N Editor: https://${N8N_EDITOR_DOMAIN}"
    echo -e "   ${ARROW} N8N Webhook: https://${N8N_WEBHOOK_DOMAIN}"
    echo ""
    echo -e "${YELLOW}⚠️  Configure sua senha de administrador no Portainer imediatamente!${RESET}"
    echo -e "   Link direto: https://${PORTAINER_DOMAIN}/#/init/admin"
    echo ""
    echo -e "${DIM}Evolution API e Dify não foram instalados conforme solicitado.${RESET}"
}

# ===== SETUP AWS (SWARM) =====
setup_aws() {
    print_step "INICIANDO SETUP AWS (DOCKER SWARM)"
    
    if [ "$EUID" -ne 0 ]; then 
       print_error "Execute com sudo ou como root"
       exit 1
    fi

    echo -e "${YELLOW}⚠️  Você escolheu o setup AWS (Swarm Architecture)${RESET}"
    read -p "$(echo -e ${BOLD}${GREEN}"Confirmar instalação AWS? (s/n): "${RESET})" CONFIRM_AWS
    if [[ ! "$CONFIRM_AWS" =~ ^(s|S|sim|SIM)$ ]]; then exit 0; fi

    IS_AWS=true

    read -p "$(echo -e ${CYAN}"🗝️  AWS_ACCESS_KEY_ID: "${RESET})" AWS_ACCESS_KEY_ID
    read -sp "$(echo -e ${CYAN}"🔒 AWS_SECRET_ACCESS_KEY: "${RESET})" AWS_SECRET_ACCESS_KEY
    echo ""
    read -p "$(echo -e ${CYAN}"🌍 Região AWS (ex: us-east-1): "${RESET})" S3_REGION
    read -p "$(echo -e ${CYAN}"🪣 Nome do Bucket S3: "${RESET})" S3_BUCKET_NAME
    echo ""

    print_step "PREPARANDO AMBIENTE AWS"
    {
        apt update -y && apt upgrade -y
        apt install -y awscli unzip curl
    } > /tmp/aws_setup.log 2>&1 &
    spinner $!

    install_docker

    print_info "Configurando AWS CLI..."
    mkdir -p /root/.aws
    cat > /root/.aws/credentials <<EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
    cat > /root/.aws/config <<EOF
[default]
region = $S3_REGION
output = json
EOF

    setup_swarm_architecture
}

# ===== SETUP GCP (SWARM) =====
setup_gcp() {
    print_step "INICIANDO SETUP GOOGLE CLOUD (DOCKER SWARM)"
    
    if [ "$EUID" -ne 0 ]; then 
       print_error "Execute com sudo ou como root"
       exit 1
    fi

    print_step "PREPARANDO AMBIENTE GCP"
    {
        apt-get update && apt-get upgrade -y
        apt-get install -y git curl gnupg lsb-release
    } > /tmp/gcp_update.log 2>&1 &
    spinner $!

    install_docker

    setup_swarm_architecture
}

# ===== MENU PRINCIPAL =====
print_banner

echo -e "Selecione o tipo de infraestrutura:"
echo -e "  [1] ${YELLOW}AWS${RESET} (Single Node / Docker Swarm)"
echo -e "  [2] ${BLUE}Google Cloud${RESET} (Multi Node / Docker Swarm)"
echo ""
read -p "Opção (1 ou 2): " CLOUD_OPTION

case $CLOUD_OPTION in
    1)
        setup_aws
        ;;
    2)
        setup_gcp
        ;;
    *)
        print_error "Opção inválida!"
        exit 1
        ;;
esac
