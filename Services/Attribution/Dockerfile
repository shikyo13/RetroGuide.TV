FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --uid 10001 --create-home attribution
COPY attribution ./attribution
RUN mkdir /data && chown attribution:attribution /data
USER attribution
EXPOSE 8080
CMD ["uvicorn", "attribution.api:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--limit-concurrency", "32", "--timeout-keep-alive", "5"]
