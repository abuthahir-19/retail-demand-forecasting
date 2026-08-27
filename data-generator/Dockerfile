FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY generate_pos_data.py .
ENTRYPOINT ["python", "generate_pos_data.py"]
