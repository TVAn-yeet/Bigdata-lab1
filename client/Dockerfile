ARG PYTHON_IMAGE
FROM ${PYTHON_IMAGE}

ARG BOTO3_VERSION
RUN test -n "${BOTO3_VERSION}" \
    && python -m pip install --no-cache-dir "boto3==${BOTO3_VERSION}"

COPY scripts/member2/s3lab.py /opt/s3lab.py
CMD ["sleep", "infinity"]
