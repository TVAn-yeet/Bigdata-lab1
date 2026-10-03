# Client image

The client image must be built outside the timed lab using the immutable Python image digest and exact boto3 version approved by teaching staff. The finished image must be published or made available to the cluster and supplied as CLIENT_IMAGE by immutable digest. Do not invent a Python tag, boto3 version or registry digest.

Example build after receiving both approved inputs:

~~~sh
docker build -f client/Dockerfile \
  --build-arg PYTHON_IMAGE="$PYTHON_IMAGE" \
  --build-arg BOTO3_VERSION="$BOTO3_VERSION" \
  -t bigdata-lab1-client:prepared .
~~~

The S3 helper uses real requests, one SDK attempt per call, explicit connect/read timeouts, deterministic synthetic data and JSONL output. This local tag is not itself a cluster-pullable immutable image reference.
