#!/bin/bash
set -e

# ==========================================
#  🚀 DIFY AI STANDALONE SETUP
#  Version: 1.0.0
#  Description: Instalação do Dify em VM separada (AWS/GCP)
#  Author: AlobExpress Team
# ==========================================

# ===== CORES ANSI =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ===== FUNÇÕES DE UI =====
print_banner() {
    clear
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}║${RESET}  ${BOLD}${CYAN}🤖 DIFY AI SETUP - STANDALONE${RESET}                               ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}╠═══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${MAGENTA}║${RESET}  ${DIM}Instalação Otimizada para AWS & Google Cloud${RESET}                ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_step() {
    echo -e "\n${BOLD}${BLUE}▶${RESET} ${BOLD}$1${RESET}"
}

print_success() {
    echo -e "  ${GREEN}✓${RESET} ${GREEN}$1${RESET}"
}

print_error() {
    echo -e "  ${RED}✗${RESET} ${RED}$1${RESET}"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"
}

print_info() {
    echo -e "  ${BLUE}ℹ${RESET} ${CYAN}$1${RESET}"
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

# ===== VERIFICAÇÕES DO SISTEMA =====
check_root() {
    if [ "$EUID" -ne 0 ]; then 
       print_error "Este script precisa ser executado como root (sudo su)"
       exit 1
    fi
}

check_resources() {
    print_step "VERIFICANDO RECURSOS DO SISTEMA"
    
    # CPU Check
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        print_error "Mínimo de 2 vCPUs requerido. Encontrado: $CPU_CORES"
        read -p "Deseja continuar mesmo assim? (s/n): " FORCE_CPU
        if [[ ! "$FORCE_CPU" =~ ^(s|S)$ ]]; then exit 1; fi
    else
        print_success "CPU: $CPU_CORES cores (OK)"
    fi

    # RAM Check
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -lt 3800 ]; then # ~4GB
        print_warning "Recomendado 4GB+ RAM. Encontrado: ${TOTAL_MEM}MB"
        print_info "O Dify é pesado. Considere aumentar a memória ou ativar SWAP."
        read -p "Deseja criar Swap de 4GB? (s/n): " CREATE_SWAP
        if [[ "$CREATE_SWAP" =~ ^(s|S)$ ]]; then
            fallocate -l 4G /swapfile
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            print_success "Swap de 4GB criado"
        fi
    else
        print_success "RAM: ${TOTAL_MEM}MB (OK)"
    fi
}

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

# ===== CONFIGURAÇÃO DE REDE =====
setup_firewall() {
    print_step "CONFIGURAÇÃO DE FIREWALL (UFW)"
    
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 5001/tcp
        # ufw enable # Não habilitar automaticamente para não bloquear SSH se mal configurado
        print_success "Regras de firewall (80, 443, 5001, 22) preparadas."
        print_warning "Certifique-se de liberar as portas no Security Group (AWS) ou Firewall (GCP)."
    else
        print_info "UFW não detectado. Pule este passo se estiver usando Security Groups da Cloud."
    fi
}

# ===== MAIN SETUP =====
print_banner
check_root
check_resources

print_step "CONFIGURAÇÃO INICIAL"

# 1. Cloud Provider
echo -e "Selecione o provedor de nuvem:"
echo -e "  [1] ${YELLOW}AWS${RESET}"
echo -e "  [2] ${BLUE}Google Cloud${RESET}"
echo -e "  [3] ${CYAN}Outro (Digital Ocean, Oracle, etc)${RESET}"
read -p "Opção: " CLOUD_PROVIDER

# 2. Main VM Integration
print_step "INTEGRAÇÃO COM VM EXISTENTE"
echo -e "${DIM}Para garantir comunicação com N8n/Evolution na outra VM.${RESET}"
read -p "$(echo -e ${CYAN}"🌐 IP da VM Principal (Existente): "${RESET})" MAIN_VM_IP

if [ -n "$MAIN_VM_IP" ]; then
    print_info "Testando conectividade com $MAIN_VM_IP..."
    if ping -c 1 "$MAIN_VM_IP" &> /dev/null; then
        print_success "Conexão com VM Principal OK!"
    else
        print_warning "Não foi possível pingar a VM Principal. Verifique as regras de Firewall/ICMP."
        print_warning "Se estiver na mesma VPC (GCP/AWS), use o IP Interno."
    fi
fi

# 3. Dify Configuration
print_step "CONFIGURAÇÃO DO DIFY"

read -p "$(echo -e ${CYAN}"🌍 Domínio do Dify Web (ex: dify.seu-dominio.com): "${RESET})" DIFY_WEB_DOMAIN
read -p "$(echo -e ${CYAN}"🌍 Domínio do Dify API (ex: api.dify.seu-dominio.com): "${RESET})" DIFY_API_DOMAIN
read -p "$(echo -e ${CYAN}"📧 E-mail para SSL (LetsEncrypt): "${RESET})" TRAEFIK_EMAIL

# Generate Secrets
DIFY_SECRET_KEY="sk-$(openssl rand -hex 20)"
POSTGRES_PASSWORD=$(openssl rand -hex 12)
REDIS_PASSWORD=$(openssl rand -hex 12)

print_info "Gerando credenciais seguras..."
print_info "Dify Secret: $DIFY_SECRET_KEY"
print_info "DB Password: $POSTGRES_PASSWORD"

# S3 Configuration
print_step "CONFIGURAÇÃO DE STORAGE (S3)"
read -p "$(echo -e ${CYAN}"🪣 Deseja usar S3 para upload de arquivos? (s/n): "${RESET})" ENABLE_S3
DIFY_S3_BLOCK="STORAGE_TYPE: local"

if [[ "$ENABLE_S3" =~ ^(s|S|sim|SIM)$ ]]; then
    read -p "S3 Endpoint: " S3_ENDPOINT
    read -p "S3 Bucket: " S3_BUCKET
    read -p "S3 Access Key: " S3_ACCESS_KEY
    read -sp "S3 Secret Key: " S3_SECRET_KEY
    echo ""
    read -p "S3 Region: " S3_REGION
    
    DIFY_S3_BLOCK=$(cat <<EOF
      STORAGE_TYPE: s3
      S3_ENDPOINT: '$S3_ENDPOINT'
      S3_BUCKET_NAME: '$S3_BUCKET'
      S3_ACCESS_KEY: '$S3_ACCESS_KEY'
      S3_SECRET_KEY: '$S3_SECRET_KEY'
      S3_REGION: '$S3_REGION'
      S3_USE_SSL: 'true'
EOF
)
fi

# ===== INSTALAÇÃO =====
print_step "INICIANDO INSTALAÇÃO"

# Install Deps
{
    apt-get update && apt-get upgrade -y
    apt-get install -y curl git
} > /tmp/deps_install.log 2>&1 &
spinner $!
print_success "Dependências do sistema atualizadas"

install_docker

# Initialize Swarm (Single Node)
if ! docker info | grep -q "Swarm: active"; then
    print_info "Inicializando Swarm (Single Node)..."
    docker swarm init > /dev/null 2>&1
fi

# Create Network
docker network create --driver overlay --attachable dify_network || true

# Generate Docker Compose (Stack)
cat <<EOF > docker-compose-dify.yaml
version: '3.7'

services:
  # === PROXY ===
  traefik:
    image: traefik:v3.6.4
    command:
      - "--providers.swarm=true"
      - "--providers.swarm.network=dify_network"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${TRAEFIK_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certs:/letsencrypt
    networks:
      - dify_network
    ports:
      - "80:80"
      - "443:443"
    deploy:
      placement:
        constraints: [node.role == manager]

  # === DATABASE (PGVECTOR) ===
  # Usado tanto para dados da aplicação quanto para vetores
  pgvector:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: dify
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - pgvector_data:/var/lib/postgresql/data
    networks:
      - dify_network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2048M

  # === CACHE ===
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - dify_network

  # === MANAGEMENT AGENT ===
  portainer_agent:
    image: portainer/agent:2.19.5
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - dify_network
    ports:
      - "9001:9001"
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  # === DIFY SERVICES ===
  dify_sandbox:
    image: langgenius/dify-sandbox:0.2.12
    environment:
      API_KEY: dify-sandbox
    networks:
      - dify_network
    cap_add:
      - SYS_ADMIN

  dify_api:
    image: langgenius/dify-api:1.11.1
    environment:
      MODE: api
      LOG_LEVEL: WARNING
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: pgvector
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      VECTOR_STORE: pgvector
      PGVECTOR_HOST: pgvector
      PGVECTOR_PORT: 5432
      PGVECTOR_USER: postgres
      PGVECTOR_PASSWORD: ${POSTGRES_PASSWORD}
      PGVECTOR_DATABASE: dify
      CODE_EXECUTION_API_KEY: dify-sandbox
      CODE_EXECUTION_ENDPOINT: http://dify_sandbox:8194
      APP_WEB_URL: https://${DIFY_WEB_DOMAIN}
      SERVICE_API_URL: https://${DIFY_API_DOMAIN}
      ${DIFY_S3_BLOCK}
    networks:
      - dify_network
    ports:
      - "5001:5001"
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.dify_api.rule=Host(\`${DIFY_API_DOMAIN}\`)"
        - "traefik.http.routers.dify_api.entrypoints=websecure"
        - "traefik.http.routers.dify_api.tls.certresolver=letsencrypt"
        - "traefik.http.services.dify_api.loadbalancer.server.port=5001"

  dify_worker:
    image: langgenius/dify-api:1.11.1
    environment:
      MODE: worker
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: pgvector
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      VECTOR_STORE: pgvector
      PGVECTOR_HOST: pgvector
      PGVECTOR_PORT: 5432
      PGVECTOR_USER: postgres
      PGVECTOR_PASSWORD: ${POSTGRES_PASSWORD}
      PGVECTOR_DATABASE: dify
      ${DIFY_S3_BLOCK}
    networks:
      - dify_network

  dify_web:
    image: langgenius/dify-web:1.11.1
    environment:
      CONSOLE_API_URL: https://${DIFY_API_DOMAIN}
      APP_API_URL: https://${DIFY_API_DOMAIN}
      SENTRY_DSN: ''
    networks:
      - dify_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.dify_web.rule=Host(\`${DIFY_WEB_DOMAIN}\`)"
        - "traefik.http.routers.dify_web.entrypoints=websecure"
        - "traefik.http.routers.dify_web.tls.certresolver=letsencrypt"
        - "traefik.http.services.dify_web.loadbalancer.server.port=3000"

volumes:
  pgvector_data:
  redis_data:
  traefik_certs:

networks:
  dify_network:
    external: true
EOF

print_step "DEPLOY DO STACK DIFY"
print_info "Iniciando serviços..."
docker stack deploy -c docker-compose-dify.yaml dify

print_info "Aguardando inicialização (60s)..."
sleep 60 &
spinner $!

# Check Migration Status
print_step "STATUS DA INSTALAÇÃO"
docker service ls

print_success "Instalação Concluída!"
echo ""
echo -e "${BOLD}${MAGENTA}🔗 ACESSO:${RESET}"
echo -e "   Frontend: https://${DIFY_WEB_DOMAIN}"
echo -e "   API: https://${DIFY_API_DOMAIN}"
echo ""
echo -e "${YELLOW}⚠️  Aponte os CNAMEs no seu DNS para o IP desta VM!${RESET}"
echo -e "   ${DIFY_WEB_DOMAIN} -> $(curl -s ifconfig.me)"
echo -e "   ${DIFY_API_DOMAIN} -> $(curl -s ifconfig.me)"
echo ""
echo -e "${BOLD}${CYAN}🔒 CREDENCIAIS INTERNAS:${RESET}"
echo -e "   Postgres: $POSTGRES_PASSWORD"
echo -e "   Redis: $REDIS_PASSWORD"
echo ""
if [ -n "$MAIN_VM_IP" ]; then
    echo -e "${BLUE}ℹ  Integração com Main VM ($MAIN_VM_IP):${RESET}"
    echo -e "   Certifique-se de liberar o tráfego desta VM (IP: $(curl -s ifconfig.me)) no firewall da Main VM."
fi

# ===== GUIA CLOUD HÍBRIDA (AWS <-> GCP) =====
MY_PUBLIC_IP=$(curl -s ifconfig.me)

echo ""
echo -e "${BOLD}${WHITE}🌐 GUIA DE CONECTIVIDADE HÍBRIDA (AWS <-> GCP/Outros)${RESET}"
echo -e "${DIM}Configure estas regras nos painéis de controle das nuvens para permitir a comunicação segura:${RESET}"
echo ""

echo -e "${YELLOW}1. No Painel da AWS (Security Group desta VM):${RESET}"
echo -e "   Adicione uma regra de entrada (Inbound):"
echo -e "   - Tipo: ${WHITE}Custom TCP${RESET}"
echo -e "   - Porta: ${WHITE}5001${RESET} (API Dify) e ${WHITE}443${RESET} (HTTPS)"
echo -e "   - Origem (Source): ${GREEN}${MAIN_VM_IP}/32${RESET} (IP da sua VM N8n/GCP)"
echo -e "   ${DIM}* Isso permite que o N8n acesse a API do Dify.${RESET}"
echo ""

echo -e "${BLUE}2. No Painel da Google Cloud / Outro (Firewall da VM N8n):${RESET}"
echo -e "   Adicione uma regra de firewall (Inbound):"
echo -e "   - Portas: ${WHITE}5678${RESET} (Webhook N8n) e ${WHITE}443${RESET}"
echo -e "   - Filtro de origem (Source IP): ${GREEN}${MY_PUBLIC_IP}/32${RESET} (IP desta VM Dify)"
echo -e "   ${DIM}* Isso permite que o Dify envie dados para o N8n.${RESET}"
echo ""
echo -e "${RED}⚠️  IMPORTANTE:${RESET} Use Elastic IP (AWS) e Static IP (GCP) para que esses IPs não mudem!"
echo ""

# Cleanup
rm -f get-docker.sh /tmp/docker_install.log /tmp/deps_install.log
