import os

from flask import Flask, jsonify


def create_app():
    app = Flask(__name__)

    @app.get("/")
    def index():
        return jsonify(message="Hello from the CI/CD pipeline!", version=os.getenv("APP_VERSION", "dev"))

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/add/<int:a>/<int:b>")
    def add(a, b):
        return jsonify(result=a + b)

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
