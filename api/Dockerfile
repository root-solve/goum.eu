FROM python:3.12-alpine

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && adduser -D -H -u 10001 app
COPY tracks_server.py .

ENV MP3_DIR=/mp3
ENV PORT=8080
EXPOSE 8080
USER app

CMD ["python", "-u", "tracks_server.py"]
