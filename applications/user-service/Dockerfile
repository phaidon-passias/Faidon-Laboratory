FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/shared-libraries/python-logging
RUN adduser --uid 10001 --disabled-password --gecos "" appuser
WORKDIR /app
COPY requirements.txt .
COPY shared-libraries/ /shared-libraries/
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install -e /shared-libraries/python-logging
COPY server.py .
RUN chown -R 10001:10001 /app
USER 10001:10001
EXPOSE 8000
CMD ["python", "server.py"]
