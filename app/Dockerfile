FROM python:3.12-slim

# 1. Ajustes de locale (se precisar de acentuação)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libjpeg-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# copia todo o seu código e assets
COPY . .

# expõe a porta do Uvicorn
EXPOSE 7000

# comando default
CMD ["uvicorn", "service:app", "--host", "0.0.0.0", "--port", "7000"]
