from setuptools import setup, find_packages

setup(
    name="faidon-laboratory-logging",
    version="0.1.0",
    description="Structured logging library with OpenTelemetry integration",
    packages=find_packages(),
    install_requires=[
        "opentelemetry-api>=1.21.0",
        "opentelemetry-sdk>=1.21.0",
        "opentelemetry-exporter-otlp>=1.21.0",
        "opentelemetry-instrumentation>=0.42b0",
    ],
    python_requires=">=3.8",
    author="Faidon Laboratory",
    author_email="faidon@example.com",
    url="https://github.com/faidon-laboratory/python-logging",
)
