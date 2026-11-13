
# ==========================================
# Stage 1: Build das dependências Python
# ==========================================
# Usa Python 3.13 sobre Debian 13 (Trixie), compatível com a imagem final.
FROM python:3.13-slim-trixie AS builder

WORKDIR /app

# Alinha o caminho do interpretador ao utilizado pelo Distroless.
# Isso evita que o ambiente virtual dependa de /usr/local/bin/python,
# que não existe necessariamente na imagem final.
RUN ln -s /usr/local/bin/python /usr/bin/python \
    && /usr/bin/python -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

# Instala o compilador somente no estágio de build.
# Nenhum pacote de compilação será copiado para a imagem final.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Instala as dependências do Targeting Service.
RUN python -m pip install --no-cache-dir -r requirements.txt

# Preserva o setuptools para compatibilidade com dependências indiretas,
# atualizando também suas bibliotecas internas.
RUN python -m pip install --no-cache-dir --upgrade setuptools==80.10.2

# Verifica conflitos de dependências e a importação das bibliotecas principais,
# incluindo o driver PostgreSQL (psycopg2).
RUN python -m pip check \
    && python -c "import flask, gunicorn, psycopg2, requests, dotenv, setuptools; print('Dependencies OK')"

# Remove apenas o pip, que não é necessário durante a execução.
# Mantém o setuptools e as dependências da aplicação.
RUN python -m pip uninstall -y pip \
    && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} + \
    && find /opt/venv -type f -name '*.pyc' -delete

# ==========================================
# Stage 2: Imagem final Distroless
# ==========================================
# Debian 13, Python 3.13 e execução como usuário não privilegiado.
FROM gcr.io/distroless/python3-debian13:nonroot

WORKDIR /app

# Copia somente o ambiente virtual pronto e o código da aplicação.
COPY --from=builder --chown=nonroot:nonroot /opt/venv /opt/venv
COPY --chown=nonroot:nonroot app.py .

# Configura o ambiente de execução do Python.
ENV PYTHONPATH="/opt/venv/lib/python3.13/site-packages"
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

USER nonroot
EXPOSE 8003

# Inicia o Gunicorn com o interpretador do ambiente virtual,
# sem depender de scripts com caminhos do Python do builder.
ENTRYPOINT ["/opt/venv/bin/python", "-m", "gunicorn"]
CMD ["--bind", "0.0.0.0:8003", "app:app"]
