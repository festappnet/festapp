FROM python:3.13-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --no-create-home broker
WORKDIR /app
COPY broker.py /app/broker.py
USER 10001:10001
CMD ["python3", "-u", "/app/broker.py"]
