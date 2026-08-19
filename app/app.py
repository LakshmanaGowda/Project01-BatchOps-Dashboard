from flask import Flask, render_template
import json

app = Flask(__name__)


@app.route("/")
def dashboard():

    with open("jobs.json") as file:
        jobs = json.load(file)

    health = "Healthy"

    return render_template(
        "index.html",
        jobs=jobs,
        health=health
    )


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000
    )